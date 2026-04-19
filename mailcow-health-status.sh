#!/usr/bin/env bash

set -euo pipefail

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then
  CHECK_ONLY=1
  shift
fi

if [ "$#" -ne 0 ]; then
  echo "usage: $0 [--check]" >&2
  exit 2
fi

MAILCOW_URL="${MAILCOW_URL:-https://mail.1kb.no}"
ADMIN_API_KEY="${ADMIN_API_KEY:-}"
GITHUB_RELEASES_URL="${GITHUB_RELEASES_URL:-https://api.github.com/repos/mailcow/mailcow-dockerized/releases/latest}"
STRICT_LATEST_VERSION="${STRICT_LATEST_VERSION:-1}"
MAX_CACHE_AGE="${MAX_CACHE_AGE:-3600}"
NTFY_BASE_URL="${NTFY_BASE_URL:-https://ntfy.sh}"
NTFY_TOPIC="${NTFY_TOPIC:-$(hostname | sed 's/\./-/g')-$(/sbin/dmidecode -t system | grep "Serial Number" | cut -d\  -f3)}"

MAILCOW_URL="${MAILCOW_URL%/}"
NTFY_BASE_URL="${NTFY_BASE_URL%/}"

respond_cache="/var/cache/$(basename "$0" .sh)-respond"
version_cache="/var/cache/$(basename "$0" .sh)-version"

notify() {
  local tags="$1"
  local title="$2"
  local priority="$3"
  local message="$4"

  if [ "$CHECK_ONLY" = "1" ]; then
    return 0
  fi

  curl -fsS \
    -H "Title: $title" \
    -H "Priority: $priority" \
    -H "tags: $tags" \
    -d "$message" \
    "$NTFY_BASE_URL/$NTFY_TOPIC"
}

cache_expired() {
  local cache_file="$1"

  if [ ! -f "$cache_file" ]; then
    return 0
  fi

  [ $(( $(date +%s) - $(date +%s -r "$cache_file") )) -gt "$MAX_CACHE_AGE" ]
}

api_get() {
  local path="$1"

  curl -fsS \
    --connect-timeout 5 \
    --max-time 30 \
    -H "X-API-Key: $ADMIN_API_KEY" \
    "$MAILCOW_URL$path"
}

github_latest_release() {
  curl -fsS \
    --connect-timeout 5 \
    --max-time 30 \
    "$GITHUB_RELEASES_URL"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "missing required command: jq" >&2
  exit 2
fi

if [ -z "$ADMIN_API_KEY" ]; then
  echo "missing ADMIN_API_KEY" >&2
  exit 2
fi

version_json=""
latest_json=""
respond_error=""
latest_error=""

if ! version_json="$(api_get "/api/v1/get/status/version" 2>&1)"; then
  respond_error="$version_json"
fi

if [ -z "$respond_error" ]; then
  current_version="$(jq -r '.version // "unknown"' <<<"$version_json")"
else
  current_version="unknown"
fi

if ! latest_json="$(github_latest_release 2>&1)"; then
  latest_error="$latest_json"
  latest_version="unknown"
  release_url=""
else
  latest_version="$(jq -r '.tag_name // "unknown"' <<<"$latest_json")"
  release_url="$(jq -r '.html_url // ""' <<<"$latest_json")"
fi

if [ -n "$respond_error" ]; then
  if cache_expired "$respond_cache"; then
    notify "email,warning" "Mailcow Health Status" "high" "Mailcow at $MAILCOW_URL is not responding to the version API: $respond_error"
    if [ "$CHECK_ONLY" != "1" ]; then
      touch "$respond_cache"
    fi
  fi
  exit 1
fi

if [ -f "$respond_cache" ]; then
  notify "email,white_check_mark" "Mailcow Health Status" "default" "Mailcow at $MAILCOW_URL is responding again."
  if [ "$CHECK_ONLY" != "1" ]; then
    rm -f "$respond_cache"
  fi
fi

if [ -n "$latest_error" ]; then
  if cache_expired "$version_cache"; then
    notify "email,warning" "Mailcow Health Status" "high" "Mailcow version check could not reach the upstream release endpoint: $latest_error"
    if [ "$CHECK_ONLY" != "1" ]; then
      touch "$version_cache"
    fi
  fi
  exit 1
fi

if [ "$current_version" = "$latest_version" ]; then
  if [ -f "$version_cache" ]; then
    notify "email,white_check_mark" "Mailcow Health Status" "default" "Mailcow at $MAILCOW_URL is up to date on version $current_version."
    if [ "$CHECK_ONLY" != "1" ]; then
      rm -f "$version_cache"
    fi
  fi
  exit 0
fi

if cache_expired "$version_cache"; then
  message="Mailcow at $MAILCOW_URL is responding, but version $current_version is behind latest upstream $latest_version."
  if [ -n "$release_url" ]; then
    message="$message Release: $release_url"
  fi
  notify "email,warning" "Mailcow Health Status" "high" "$message"
  if [ "$CHECK_ONLY" != "1" ]; then
    touch "$version_cache"
  fi
fi

if [ "$STRICT_LATEST_VERSION" = "1" ]; then
  exit 1
fi

exit 0
