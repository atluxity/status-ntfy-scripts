#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=status-ntfy-lib.sh
. "$SCRIPT_DIR/status-ntfy-lib.sh"

REQUIRED="${IPMI_REQUIRED:-0}"
IPMITOOL_BIN="${IPMITOOL_BIN:-}"
CHECK_POWER=1
CHECK_FANS=1
CHECK_TEMP=1

usage() {
  echo "usage: $0 [--required] [--power-only] [--ipmitool PATH] [--topic TOPIC] [--cache-dir DIR] [--env-file FILE] [--no-notify]" >&2
}

while [ "$#" -gt 0 ]; do
  common_arg "$@"
  consumed=$?
  if [ "$consumed" -gt 0 ]; then
    shift "$consumed"
    continue
  fi

  case "$1" in
    --required|--require-tool)
      REQUIRED=1
      shift
      ;;
    --ipmitool)
      IPMITOOL_BIN="$2"
      shift 2
      ;;
    --ipmitool=*)
      IPMITOOL_BIN="${1#*=}"
      shift
      ;;
    --power-only)
      CHECK_POWER=1
      CHECK_FANS=0
      CHECK_TEMP=0
      shift
      ;;
    --no-power)
      CHECK_POWER=0
      shift
      ;;
    --no-fans)
      CHECK_FANS=0
      shift
      ;;
    --no-temp)
      CHECK_TEMP=0
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

find_ipmitool() {
  if [ -n "$IPMITOOL_BIN" ]; then
    printf '%s' "$IPMITOOL_BIN"
    return 0
  fi
  command -v ipmitool 2>/dev/null
}

ipmitool_bin="$(find_ipmitool || true)"
if [ -z "$ipmitool_bin" ] || [ ! -x "$ipmitool_bin" ]; then
  message="IPMI platform check could not find ipmitool."
  if [ "$REQUIRED" = "1" ]; then
    record_check_state "tool-missing" 1 "IPMI Platform Status" "high" "computer,warning" "$message" "ipmitool is available again."
    exit 1
  fi
  echo "$message Skipping optional check." >&2
  exit 0
fi

sensor_output="$("$ipmitool_bin" sensor 2>&1)"
sensor_rc=$?
findings=""

if [ "$sensor_rc" -ne 0 ]; then
  findings="ipmitool sensor failed: $sensor_output"
else
  findings="$(printf '%s\n' "$sensor_output" | awk -F'|' -v power="$CHECK_POWER" -v fans="$CHECK_FANS" -v temp="$CHECK_TEMP" '
    function trim(value) {
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      return value
    }
    {
      name=trim($1)
      lowered=tolower(name)
      status=tolower(trim($4))
      match_sensor=0
      if (power == 1 && lowered ~ /(power|pwr|psu|supply)/) match_sensor=1
      if (fans == 1 && lowered ~ /fan/) match_sensor=1
      if (temp == 1 && lowered ~ /(temp|thermal|ambient)/) match_sensor=1
      if (match_sensor == 1 && status != "ok" && status != "na" && status !~ /^0x[0-9a-f]+$/) print $0
    }')"
fi

if [ -n "$findings" ]; then
  message="IPMI platform sensors report unhealthy hardware:"$'\n'"$findings"
  record_check_state "ipmi-platform" 1 "IPMI Platform Status" "high" "computer,warning" "$message" "IPMI platform sensors are healthy again."
  exit 1
fi

record_check_state "ipmi-platform" 0 "IPMI Platform Status" "high" "computer,warning" "" "IPMI platform sensors are healthy again."
echo "IPMI platform sensors OK"
exit 0
