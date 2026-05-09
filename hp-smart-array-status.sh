#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=status-ntfy-lib.sh
. "$SCRIPT_DIR/status-ntfy-lib.sh"

SLOT="${SMART_ARRAY_SLOT:-0}"
REQUIRED="${SMART_ARRAY_REQUIRED:-0}"
SSACLI_BIN="${SSACLI_BIN:-}"

usage() {
  echo "usage: $0 [--slot N] [--required] [--ssacli PATH] [--topic TOPIC] [--cache-dir DIR] [--env-file FILE] [--no-notify]" >&2
}

while [ "$#" -gt 0 ]; do
  common_arg "$@"
  consumed=$?
  if [ "$consumed" -gt 0 ]; then
    shift "$consumed"
    continue
  fi

  case "$1" in
    --slot)
      SLOT="$2"
      shift 2
      ;;
    --slot=*)
      SLOT="${1#*=}"
      shift
      ;;
    --required|--require-tool)
      REQUIRED=1
      shift
      ;;
    --ssacli)
      SSACLI_BIN="$2"
      shift 2
      ;;
    --ssacli=*)
      SSACLI_BIN="${1#*=}"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

init_status_ntfy

find_ssacli() {
  if [ -n "$SSACLI_BIN" ]; then
    printf '%s' "$SSACLI_BIN"
    return 0
  fi

  if command -v ssacli >/dev/null 2>&1; then
    command -v ssacli
    return 0
  fi
  if command -v hpssacli >/dev/null 2>&1; then
    command -v hpssacli
    return 0
  fi
  if [ -x /sbin/ssacli ]; then
    printf '%s' /sbin/ssacli
    return 0
  fi
  if [ -x /sbin/hpssacli ]; then
    printf '%s' /sbin/hpssacli
    return 0
  fi

  return 1
}

ssacli="$(find_ssacli || true)"
if [ -z "$ssacli" ] || [ ! -x "$ssacli" ]; then
  message="Smart Array check could not find ssacli or hpssacli."
  if [ "$REQUIRED" = "1" ]; then
    record_check_state "tool-missing" 1 "HP Smart Array Status" "high" "computer,warning" "$message" "Smart Array tool is available again."
    exit 1
  fi
  echo "$message Skipping optional check." >&2
  exit 0
fi

controller_status="$("$ssacli" ctrl all show status 2>&1)"
controller_rc=$?
pd_status="$("$ssacli" ctrl "slot=$SLOT" pd all show status 2>&1)"
pd_rc=$?
ld_status="$("$ssacli" ctrl "slot=$SLOT" ld all show status 2>&1)"
ld_rc=$?
config_detail="$("$ssacli" ctrl "slot=$SLOT" show config detail 2>&1)"
config_rc=$?

findings=""

append_findings() {
  local value="$1"
  if [ -n "$value" ]; then
    findings="${findings}${value}"$'\n'
  fi
}

if [ "$controller_rc" -ne 0 ]; then
  append_findings "ssacli controller status failed: $controller_status"
fi
if [ "$pd_rc" -ne 0 ]; then
  append_findings "ssacli physical drive status failed: $pd_status"
fi
if [ "$ld_rc" -ne 0 ]; then
  append_findings "ssacli logical drive status failed: $ld_status"
fi
if [ "$config_rc" -ne 0 ]; then
  append_findings "ssacli config detail failed: $config_detail"
fi

append_findings "$(printf '%s\n' "$controller_status" | awk -F: '
  /Status:/ {
    value=$NF
    gsub(/^[ \t]+|[ \t]+$/, "", value)
    if (value != "OK") print $0
  }')"

append_findings "$(printf '%s\n' "$pd_status" | awk -F: '
  /physicaldrive/ {
    value=$NF
    gsub(/^[ \t]+|[ \t]+$/, "", value)
    if (value != "OK") print $0
  }')"

append_findings "$(printf '%s\n' "$ld_status" | awk -F: '
  /logicaldrive/ {
    value=$NF
    gsub(/^[ \t]+|[ \t]+$/, "", value)
    if (value != "OK") print $0
  }')"

append_findings "$(printf '%s\n' "$config_detail" | awk -F: '
  /Predictive Failure|Failed physical drive/ { print; next }
  /^[ \t]*(Controller Status|Cache Status|Battery\/Capacitor Status|Array Status|Status):/ {
    value=$NF
    gsub(/^[ \t]+|[ \t]+$/, "", value)
    if (value != "OK") print $0
  }
  /^[ \t]*(physicaldrive|logicaldrive|array)[ \t].*:/ {
    value=$NF
    gsub(/^[ \t]+|[ \t]+$/, "", value)
    if (value != "OK") print $0
  }
  {
    lowered=tolower($0)
    if (lowered ~ /spare/ && lowered ~ /(missing|failed|predictive|not ok|unassigned)/) print
  }
')"

findings="$(printf '%s\n' "$findings" | sed '/^[[:space:]]*$/d' | sort -u)"

if [ -n "$findings" ]; then
  message="Smart Array slot $SLOT reports unhealthy hardware:"$'\n'"$findings"
  record_check_state "smart-array" 1 "HP Smart Array Status" "high" "computer,warning" "$message" "Smart Array slot $SLOT is healthy again."
  exit 1
fi

record_check_state "smart-array" 0 "HP Smart Array Status" "high" "computer,warning" "" "Smart Array slot $SLOT is healthy again."
echo "Smart Array slot $SLOT OK"
exit 0
