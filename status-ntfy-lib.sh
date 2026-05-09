#!/usr/bin/env bash

set -u

SCRIPT_NAME="$(basename "$0" .sh)"
NOTIFY="${NOTIFY:-1}"
ENV_FILE="${ENV_FILE:-}"
CACHE_DIR="${CACHE_DIR:-}"
MAX_CACHE_AGE="${MAX_CACHE_AGE:-}"
NTFY_BASE_URL="${NTFY_BASE_URL:-}"
NTFY_TOPIC="${NTFY_TOPIC:-}"

read_env_value() {
  local key="$1"
  local file="$2"

  grep -E "^${key}=" "$file" | tail -n 1 | cut -d= -f2-
}

load_env_file() {
  local file="$1"

  if [ -z "$file" ] || [ ! -f "$file" ]; then
    return 0
  fi

  if [ -z "${NTFY_BASE_URL:-}" ]; then
    NTFY_BASE_URL="$(read_env_value "NTFY_BASE_URL" "$file" || true)"
  fi
  if [ -z "${NTFY_TOPIC:-}" ]; then
    NTFY_TOPIC="$(read_env_value "NTFY_TOPIC" "$file" || true)"
  fi
  if [ -z "${CACHE_DIR:-}" ]; then
    CACHE_DIR="$(read_env_value "CACHE_DIR" "$file" || true)"
  fi
  if [ -z "${MAX_CACHE_AGE:-}" ]; then
    MAX_CACHE_AGE="$(read_env_value "MAX_CACHE_AGE" "$file" || true)"
  fi
}

generated_topic() {
  local host
  local serial

  host="$(hostname | sed 's/\./-/g')"
  serial=""
  if command -v dmidecode >/dev/null 2>&1; then
    serial="$(dmidecode -t system 2>/dev/null | awk -F: '/Serial Number/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
  elif [ -x /sbin/dmidecode ]; then
    serial="$(/sbin/dmidecode -t system 2>/dev/null | awk -F: '/Serial Number/ {gsub(/^[ \t]+/, "", $2); print $2; exit}')"
  fi

  if [ -n "$serial" ]; then
    printf '%s-%s' "$host" "$serial" | tr '[:upper:]' '[:lower:]'
  else
    printf '%s' "$host" | tr '[:upper:]' '[:lower:]'
  fi
}

init_status_ntfy() {
  load_env_file "$ENV_FILE"

  NTFY_BASE_URL="${NTFY_BASE_URL:-https://ntfy.sh}"
  CACHE_DIR="${CACHE_DIR:-/var/cache/hardware-alerts}"
  MAX_CACHE_AGE="${MAX_CACHE_AGE:-3600}"
  if [ -z "${NTFY_TOPIC:-}" ]; then
    NTFY_TOPIC="$(generated_topic)"
  fi
  NTFY_BASE_URL="${NTFY_BASE_URL%/}"
}

cache_file_for() {
  local key="$1"
  key="$(printf '%s' "$key" | tr -c 'A-Za-z0-9_.-' '_')"
  printf '%s/%s-%s.cache' "$CACHE_DIR" "$SCRIPT_NAME" "$key"
}

cache_expired() {
  local cache_file="$1"

  if [ ! -f "$cache_file" ]; then
    return 0
  fi

  [ $(( $(date +%s) - $(date +%s -r "$cache_file") )) -gt "$MAX_CACHE_AGE" ]
}

notify_ntfy() {
  local tags="$1"
  local title="$2"
  local priority="$3"
  local message="$4"

  if [ "$NOTIFY" != "1" ]; then
    printf '%s\n%s\n' "$title" "$message" >&2
    return 0
  fi

  curl -fsS \
    -H "Title: $title" \
    -H "Priority: $priority" \
    -H "tags: $tags" \
    -d "$message" \
    "$NTFY_BASE_URL/$NTFY_TOPIC"
}

record_check_state() {
  local key="$1"
  local failed="$2"
  local title="$3"
  local priority="$4"
  local tags="$5"
  local failure_message="$6"
  local recovery_message="$7"
  local cache_file

  cache_file="$(cache_file_for "$key")"

  if [ "$failed" = "1" ]; then
    if cache_expired "$cache_file"; then
      if notify_ntfy "$tags" "$title" "$priority" "$failure_message"; then
        if [ "$NOTIFY" = "1" ]; then
          mkdir -p "$CACHE_DIR"
          touch "$cache_file"
        fi
      fi
    fi
    return 1
  fi

  if [ -f "$cache_file" ]; then
    if notify_ntfy "${tags%,warning},white_check_mark" "$title" "default" "$recovery_message"; then
      if [ "$NOTIFY" = "1" ]; then
        rm -f "$cache_file"
      fi
    fi
  fi

  return 0
}

common_arg() {
  case "$1" in
    --topic)
      NTFY_TOPIC="$2"
      return 2
      ;;
    --topic=*)
      NTFY_TOPIC="${1#*=}"
      return 1
      ;;
    --cache-dir)
      CACHE_DIR="$2"
      return 2
      ;;
    --cache-dir=*)
      CACHE_DIR="${1#*=}"
      return 1
      ;;
    --env-file)
      ENV_FILE="$2"
      return 2
      ;;
    --env-file=*)
      ENV_FILE="${1#*=}"
      return 1
      ;;
    --notify)
      NOTIFY=1
      return 1
      ;;
    --no-notify|--check|--status-only)
      NOTIFY=0
      return 1
      ;;
  esac

  return 0
}
