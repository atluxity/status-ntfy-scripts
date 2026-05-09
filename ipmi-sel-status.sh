#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=status-ntfy-lib.sh
. "$SCRIPT_DIR/status-ntfy-lib.sh"

REQUIRED="${IPMI_SEL_REQUIRED:-0}"
IPMITOOL_BIN="${IPMITOOL_BIN:-}"

usage() {
  echo "usage: $0 [--required] [--ipmitool PATH] [--topic TOPIC] [--cache-dir DIR] [--env-file FILE] [--no-notify]" >&2
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
  message="IPMI SEL check could not find ipmitool."
  if [ "$REQUIRED" = "1" ]; then
    record_check_state "tool-missing" 1 "IPMI SEL Status" "high" "computer,warning" "$message" "ipmitool is available again."
    exit 1
  fi
  echo "$message Skipping optional check." >&2
  exit 0
fi

mkdir -p "$CACHE_DIR"
state_file="$CACHE_DIR/$SCRIPT_NAME-last-seen"
sel_output="$("$ipmitool_bin" sel list 2>&1)"
sel_rc=$?
if [ "$sel_rc" -ne 0 ]; then
  message="ipmitool sel list failed: $sel_output"
  record_check_state "ipmi-sel-error" 1 "IPMI SEL Status" "high" "computer,warning" "$message" "IPMI SEL can be read again."
  exit 1
fi

last_seen="0"
first_run=0
if [ -f "$state_file" ]; then
  last_seen="$(cat "$state_file")"
else
  first_run=1
fi

new_entries=""
max_seen=0
while IFS= read -r line; do
  case "$line" in
    *"|"*)
      id="${line%%|*}"
      id="$(printf '%s' "$id" | tr -d '[:space:]')"
      case "$id" in
        *[!0-9a-fA-F]*|"")
          continue
          ;;
      esac
      numeric="$((16#$id))"
      if [ "$numeric" -gt "$max_seen" ]; then
        max_seen="$numeric"
      fi
      if [ "$numeric" -gt "$last_seen" ]; then
        new_entries="${new_entries}${line}"$'\n'
      fi
      ;;
  esac
done <<EOF
$sel_output
EOF

new_entries="$(printf '%s\n' "$new_entries" | sed '/^[[:space:]]*$/d')"

if [ "$first_run" = "1" ]; then
  printf '%s\n' "$max_seen" > "$state_file"
  echo "Initialized IPMI SEL baseline at event $max_seen"
  exit 0
fi

if [ -n "$new_entries" ]; then
  message="New IPMI SEL entries:"$'\n'"$new_entries"
  if record_check_state "ipmi-sel" 1 "IPMI SEL Status" "high" "computer,warning" "$message" "No new IPMI SEL entries."; then
    :
  fi
  printf '%s\n' "$max_seen" > "$state_file"
  exit 1
fi

record_check_state "ipmi-sel" 0 "IPMI SEL Status" "high" "computer,warning" "" "No new IPMI SEL entries."
printf '%s\n' "$max_seen" > "$state_file"
echo "No new IPMI SEL entries"
exit 0
