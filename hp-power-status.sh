#!/bin/bash

NTFY_BASE_URL="${NTFY_BASE_URL:-https://ntfy.sh}"
if [ -z "${NTFY_TOPIC:-}" ]; then
	raw_ntfy_topic="$(hostname | sed 's/\./-/g')-$(/sbin/dmidecode -t system | grep "Serial Number" | cut -d\  -f3)"
	NTFY_TOPIC="$(printf '%s' "$raw_ntfy_topic" | tr '[:upper:]' '[:lower:]')"
fi
NTFY_URL="${NTFY_BASE_URL%/}/$NTFY_TOPIC"

present=$(/sbin/hpasmcli -s "show powersupply" | grep -ci "Present  : Yes" )
redundant=$(/sbin/hpasmcli -s "show powersupply" | grep -ci "Redundant: Yes" )
condition=$(/sbin/hpasmcli -s "show powersupply" | grep -ci "Condition: Ok" )

presentfile="/var/cache/$(basename "$0" .sh)-present"
redundantfile="/var/cache/$(basename "$0" .sh)-redundant"
conditionfile="/var/cache/$(basename "$0" .sh)-condition"


if [ ! -f "$presentfile" ] || [ $(( $(date +%s) - $(date +%s -r "$presentfile") )) -gt 3600 ]; then
	if [ "$present" -ne 2 ]; then
		curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,warning" -d "Powersupply missing." "$NTFY_URL" &&
		touch "$presentfile"
	fi
fi

if [ ! -f "$redundantfile" ] || [ $(( $(date +%s) - $(date +%s -r "$redundantfile") )) -gt 3600 ]; then
	if [ "$redundant" -ne 2 ]; then
		curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,warning" -d "Power not redundant." "$NTFY_URL" &&
		touch "$redundantfile"
	fi
fi

if [ ! -f "$conditionfile" ] || [ $(( $(date +%s) - $(date +%s -r "$conditionfile") )) -gt 3600 ]; then
	if [ "$condition" -ne 2 ]; then 
		curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,warning" -d "Power supply NOT OK." "$NTFY_URL" &&
		touch "$conditionfile" 
	fi 
fi

if [ -f "$presentfile" ]; then
        if [ "$present" -eq 2 ]; then
                curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,white_check_mark" -d "2 Powersupplies present." "$NTFY_URL" &&
                rm "$presentfile" 
        fi 
fi

if [ -f "$redundantfile" ]; then
        if [ "$redundant" -eq 2 ]; then
                curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,white_check_mark" -d "Power redundant." "$NTFY_URL" &&
                rm "$redundantfile"
        fi
fi

if [ -f "$conditionfile" ]; then
        if [ "$condition" -eq 2 ]; then
                curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,white_check_mark" -d "Both powersupplies OK." "$NTFY_URL" &&
                rm "$conditionfile"
        fi
fi
