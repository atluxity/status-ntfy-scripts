#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export CACHE_DIR="$TEST_ROOT/cache"
export NTFY_TOPIC="test-topic"
export NTFY_BASE_URL="http://127.0.0.1:9"
mkdir -p "$CACHE_DIR" "$TEST_ROOT/bin"

pass_count=0
fail_count=0

pass() {
  pass_count=$((pass_count + 1))
  printf 'ok - %s\n' "$1"
}

fail() {
  fail_count=$((fail_count + 1))
  printf 'not ok - %s\n%s\n' "$1" "$2" >&2
}

assert_status() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  local output="$4"

  if [ "$actual" -ne "$expected" ]; then
    fail "$name" "expected exit $expected, got $actual; output: $output"
    return 1
  fi
  return 0
}

assert_contains() {
  local name="$1"
  local needle="$2"
  local output="$3"

  case "$output" in
    *"$needle"*)
      return 0
      ;;
    *)
      fail "$name" "expected output to contain '$needle'; output: $output"
      return 1
      ;;
  esac
}

write_fake_ssacli() {
  cat >"$TEST_ROOT/bin/ssacli" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "ctrl all show status")
    echo "Smart Array P410i in Slot 0"
    echo "   Controller Status: OK"
    ;;
  "ctrl slot=0 pd all show status")
    if [ "${SMART_SCENARIO:-ok}" = "predictive" ]; then
      echo "physicaldrive 2I:1:7 (port 2I:box 1:bay 7, 300 GB): Predictive Failure"
    else
      echo "physicaldrive 2I:1:7 (port 2I:box 1:bay 7, 300 GB): OK"
    fi
    ;;
  "ctrl slot=0 ld all show status")
    echo "logicaldrive 1 (1.64 TB, RAID 5): OK"
    ;;
  "ctrl slot=0 show config detail")
    echo "Controller Status: OK"
    echo "Cache Status: OK"
    echo "Battery/Capacitor Status: OK"
    if [ "${SMART_SCENARIO:-ok}" = "predictive" ]; then
      echo "physicaldrive 2I:1:7 (port 2I:box 1:bay 7, 300 GB): Predictive Failure"
    fi
    ;;
esac
EOF
  chmod +x "$TEST_ROOT/bin/ssacli"
}

write_fake_ipmitool() {
  cat >"$TEST_ROOT/bin/ipmitool" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  sensor)
    if [ "${IPMI_SCENARIO:-ok}" = "badfan" ]; then
      echo "Fan 1 | 0 RPM | nr | na | na | na | na | na | na | cr"
    else
      echo "Power Supply 1 | 1 | discrete | 0x0100 | na | na | na | na | na | ok"
      echo "Fan 1 | 4000 RPM | ok | na | na | na | na | na | na | ok"
      echo "Temp 1 | 30 degrees C | ok | na | na | na | na | na | na | ok"
    fi
    ;;
  sel)
    echo "0001 | 05/09/2026 | 12:00:00 | Power Supply | Presence detected | Asserted"
    if [ "${SEL_SCENARIO:-one}" = "two" ]; then
      echo "0002 | 05/09/2026 | 12:05:00 | Memory | Correctable ECC | Asserted"
    fi
    ;;
esac
EOF
  chmod +x "$TEST_ROOT/bin/ipmitool"
}

write_fake_journalctl() {
  cat >"$TEST_ROOT/bin/journalctl" <<'EOF'
#!/usr/bin/env bash
if [ "${JOURNAL_SCENARIO:-ok}" = "ecc" ]; then
  echo "May 09 12:00:00 host kernel: EDAC MC0: 1 CE memory read error"
fi
EOF
  chmod +x "$TEST_ROOT/bin/journalctl"
}

write_fake_df() {
  cat >"$TEST_ROOT/bin/df" <<'EOF'
#!/usr/bin/env bash
echo "Filesystem  Size  Used Avail Use% Mounted on"
case "${DF_SCENARIO:-ok}" in
  high)
    echo "/dev/sda1  100G  96G  4G  96% /"
    ;;
  warn)
    echo "/dev/sda1  100G  88G  12G  88% /"
    ;;
  *)
    echo "/dev/sda1  100G  50G  50G  50% /"
    ;;
esac
EOF
  chmod +x "$TEST_ROOT/bin/df"
}

run_case() {
  local name="$1"
  local expected_status="$2"
  local expected_text="$3"
  shift 3
  local output
  local status

  output="$("$@" 2>&1)"
  status=$?

  if assert_status "$name" "$expected_status" "$status" "$output" && assert_contains "$name" "$expected_text" "$output"; then
    pass "$name"
  fi
}

write_fake_ssacli
export SMART_SCENARIO=predictive
run_case \
  "smart array predictive failure exits nonzero" \
  1 \
  "Predictive Failure" \
  "$ROOT_DIR/hp-smart-array-status.sh" --ssacli "$TEST_ROOT/bin/ssacli" --no-notify

unset SMART_SCENARIO
run_case \
  "smart array healthy exits zero" \
  0 \
  "Smart Array slot 0 OK" \
  "$ROOT_DIR/hp-smart-array-status.sh" --ssacli "$TEST_ROOT/bin/ssacli" --no-notify

write_fake_ipmitool
export IPMI_SCENARIO=badfan
run_case \
  "ipmi platform catches unhealthy fan status" \
  1 \
  "Fan 1" \
  "$ROOT_DIR/ipmi-platform-status.sh" --ipmitool "$TEST_ROOT/bin/ipmitool" --no-notify

write_fake_journalctl
export JOURNAL_SCENARIO=ecc
run_case \
  "hardware journal catches ECC signatures" \
  1 \
  "EDAC" \
  "$ROOT_DIR/hardware-journal-status.sh" --journalctl "$TEST_ROOT/bin/journalctl" --no-notify

write_fake_df
export DF_SCENARIO=high
run_case \
  "filesystem capacity high threshold exits nonzero" \
  1 \
  "96% used" \
  "$ROOT_DIR/filesystem-capacity-status.sh" --df "$TEST_ROOT/bin/df" --path / --no-notify

export SEL_SCENARIO=one
run_case \
  "ipmi sel baselines first run" \
  0 \
  "Initialized IPMI SEL baseline" \
  "$ROOT_DIR/ipmi-sel-status.sh" --ipmitool "$TEST_ROOT/bin/ipmitool" --no-notify

export SEL_SCENARIO=two
run_case \
  "ipmi sel alerts on later new event" \
  1 \
  "Correctable ECC" \
  "$ROOT_DIR/ipmi-sel-status.sh" --ipmitool "$TEST_ROOT/bin/ipmitool" --no-notify

printf '%s passed, %s failed\n' "$pass_count" "$fail_count"

if [ "$fail_count" -ne 0 ]; then
  exit 1
fi
