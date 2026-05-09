#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=status-ntfy-lib.sh
. "$SCRIPT_DIR/status-ntfy-lib.sh"

PATHS=()
WARN_DEFAULT="${FILESYSTEM_WARN_USED:-85}"
HIGH_DEFAULT="${FILESYSTEM_HIGH_USED:-95}"
DF_BIN="${DF_BIN:-df}"
REQUIRED="${FILESYSTEM_REQUIRED:-1}"

usage() {
  echo "usage: $0 --path PATH[:WARN[:HIGH]] [--warn-used PCT] [--high-used PCT] [--topic TOPIC] [--cache-dir DIR] [--env-file FILE] [--no-notify]" >&2
}

while [ "$#" -gt 0 ]; do
  common_arg "$@"
  consumed=$?
  if [ "$consumed" -gt 0 ]; then
    shift "$consumed"
    continue
  fi

  case "$1" in
    --path)
      PATHS+=("$2")
      shift 2
      ;;
    --path=*)
      PATHS+=("${1#*=}")
      shift
      ;;
    --warn-used)
      WARN_DEFAULT="$2"
      shift 2
      ;;
    --warn-used=*)
      WARN_DEFAULT="${1#*=}"
      shift
      ;;
    --high-used)
      HIGH_DEFAULT="$2"
      shift 2
      ;;
    --high-used=*)
      HIGH_DEFAULT="${1#*=}"
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
    --df)
      DF_BIN="$2"
      shift 2
      ;;
    --df=*)
      DF_BIN="${1#*=}"
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

if [ "${#PATHS[@]}" -eq 0 ]; then
  PATHS=("/")
fi

if ! command -v "$DF_BIN" >/dev/null 2>&1 && [ ! -x "$DF_BIN" ]; then
  message="Filesystem capacity check could not find df command: $DF_BIN"
  if [ "$REQUIRED" = "1" ]; then
    record_check_state "tool-missing" 1 "Filesystem Capacity Status" "high" "floppy_disk,warning" "$message" "df is available again."
    exit 1
  fi
  echo "$message Skipping optional check." >&2
  exit 0
fi

findings=""
priority="warning"

for path_spec in "${PATHS[@]}"; do
  path="$path_spec"
  warn="$WARN_DEFAULT"
  high="$HIGH_DEFAULT"

  if [[ "$path_spec" == *:* ]]; then
    IFS=: read -r path warn high <<<"$path_spec"
    warn="${warn:-$WARN_DEFAULT}"
    high="${high:-$HIGH_DEFAULT}"
  fi

  line="$("$DF_BIN" -P -h "$path" 2>&1 | tail -n 1)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    findings="${findings}df failed for $path: $line"$'\n'
    priority="high"
    continue
  fi

  used="$(printf '%s\n' "$line" | awk '{gsub(/%/, "", $5); print $5}')"
  avail="$(printf '%s\n' "$line" | awk '{print $4}')"
  mount="$(printf '%s\n' "$line" | awk '{print $6}')"

  if [ -z "$used" ]; then
    findings="${findings}Could not parse df output for $path: $line"$'\n'
    priority="high"
    continue
  fi

  if [ "$used" -ge "$high" ]; then
    findings="${findings}${mount} is ${used}% used (${avail} free), high threshold ${high}%"$'\n'
    priority="high"
  elif [ "$used" -ge "$warn" ]; then
    findings="${findings}${mount} is ${used}% used (${avail} free), warning threshold ${warn}%"$'\n'
  fi
done

if [ -n "$findings" ]; then
  message="Filesystem capacity thresholds exceeded:"$'\n'"$findings"
  record_check_state "filesystem-capacity" 1 "Filesystem Capacity Status" "$priority" "floppy_disk,warning" "$message" "Filesystem capacity is below configured thresholds again."
  exit 1
fi

record_check_state "filesystem-capacity" 0 "Filesystem Capacity Status" "warning" "floppy_disk,warning" "" "Filesystem capacity is below configured thresholds again."
echo "Filesystem capacity OK"
exit 0
