#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=status-ntfy-lib.sh
. "$SCRIPT_DIR/status-ntfy-lib.sh"

SINCE="${HARDWARE_JOURNAL_SINCE:-1 hour ago}"
REQUIRED="${JOURNAL_REQUIRED:-1}"
JOURNALCTL_BIN="${JOURNALCTL_BIN:-}"

usage() {
  echo "usage: $0 [--since VALUE] [--required] [--journalctl PATH] [--topic TOPIC] [--cache-dir DIR] [--env-file FILE] [--no-notify]" >&2
}

while [ "$#" -gt 0 ]; do
  common_arg "$@"
  consumed=$?
  if [ "$consumed" -gt 0 ]; then
    shift "$consumed"
    continue
  fi

  case "$1" in
    --since)
      SINCE="$2"
      shift 2
      ;;
    --since=*)
      SINCE="${1#*=}"
      shift
      ;;
    --required|--require-tool)
      REQUIRED=1
      shift
      ;;
    --optional)
      REQUIRED=0
      shift
      ;;
    --journalctl)
      JOURNALCTL_BIN="$2"
      shift 2
      ;;
    --journalctl=*)
      JOURNALCTL_BIN="${1#*=}"
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

find_journalctl() {
  if [ -n "$JOURNALCTL_BIN" ]; then
    printf '%s' "$JOURNALCTL_BIN"
    return 0
  fi
  command -v journalctl 2>/dev/null
}

journalctl_bin="$(find_journalctl || true)"
if [ -z "$journalctl_bin" ] || [ ! -x "$journalctl_bin" ]; then
  message="Hardware journal check could not find journalctl."
  if [ "$REQUIRED" = "1" ]; then
    record_check_state "tool-missing" 1 "Hardware Journal Status" "high" "computer,warning" "$message" "journalctl is available again."
    exit 1
  fi
  echo "$message Skipping optional check." >&2
  exit 0
fi

journal_output="$("$journalctl_bin" -k --since "$SINCE" --no-pager 2>&1)"
journal_rc=$?
if [ "$journal_rc" -ne 0 ]; then
  message="journalctl failed for hardware journal check: $journal_output"
  record_check_state "journalctl-error" 1 "Hardware Journal Status" "high" "computer,warning" "$message" "Hardware journal check can read the journal again."
  exit 1
fi

matches="$(printf '%s\n' "$journal_output" | grep -Ei 'EDAC|MCE|machine check|memory error|ECC|I/O error|medium error|read error|write error|thermal|overheat' || true)"

if [ -z "$matches" ]; then
  record_check_state "hardware-journal" 0 "Hardware Journal Status" "high" "computer,warning" "" "No recent hardware error signatures in the journal."
  echo "No recent hardware error signatures in journal since $SINCE"
  exit 0
fi

priority="warning"
if printf '%s\n' "$matches" | grep -Eiq 'uncorrected|fatal|panic|machine check|MCE|I/O error|medium error|thermal.*critical|critical.*thermal|overheat'; then
  priority="high"
fi

message="Hardware-related journal signatures since $SINCE:"$'\n'"$(printf '%s\n' "$matches" | tail -n 40)"
record_check_state "hardware-journal" 1 "Hardware Journal Status" "$priority" "computer,warning" "$message" "No recent hardware error signatures in the journal."
exit 1
