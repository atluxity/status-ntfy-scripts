#!/bin/bash

# Set the URL to check
URL="http://mail.1kb.no"

# Set the cache file path
CACHE_FILE="/var/cache/$(basename "$0").cache"

# Set the notification service URL
NTFY_URL="https://ntfy.sh/"$(hostname | sed 's/\./-/g')-$(/sbin/dmidecode -t system | grep "Serial Number" | cut -d\  -f3)

# Set the notification title
TITLE="Website Status"

# Set the notification message
MESSAGE="Website $URL is not responding properly"

# Set the maximum age of the cache file in seconds (1 hour)
MAX_CACHE_AGE=3600

# Fetch the HTTP status code
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$URL")
#HTTP_STATUS=502

# Check if the cache file exists and is less than MAX_CACHE_AGE seconds old
if [[ -f "$CACHE_FILE" ]]; then
    AGE=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE")))
    if (( AGE < MAX_CACHE_AGE )); then
        if (( HTTP_STATUS == 200 )); then
        curl "$NTFY_URL" -H "Title: $TITLE" -H "tags: email,white_check_mark" -d "Website $URL is OK"
        rm -f "$CACHE_FILE"
        exit 0
        fi
    exit 0
    fi
fi


CURRENT_HOUR=$(date +%H)

# Check if the HTTP status code is not 200
if (( HTTP_STATUS != 200 )); then
    # Check if the time is between midnight and 6 AM
    if (( CURRENT_HOUR >= 0 && CURRENT_HOUR < 6 )); then
            sleep 300
            HTTP_STATUS_RETRY=$(curl -s -o /dev/null -w "%{http_code}" "$URL")
            if (( HTTP_STATUS_RETRY eq 200 )); then
                exit 0
            fi
    fi
    # Record the fail state in the cache file
    echo "$(date +%s)" > "$CACHE_FILE"
    # Send a push notification using NTFY
    curl "$NTFY_URL" -H "Title: $TITLE" -H "Priority: high" -H "tags: email,warning" -d "$MESSAGE"
else
    # If the error state resolves itself, clear the cache file
    rm -f "$CACHE_FILE"
fi

