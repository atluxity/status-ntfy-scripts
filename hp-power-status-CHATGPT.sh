#!/bin/bash

NTFY_TOPIC=$(hostname | tr '.' '-')-$(/sbin/dmidecode -t system | grep "Serial Number" | awk -F ': ' '/Serial Number/ {print $2}')

present=$(/sbin/hpasmcli -s "show powersupply" | grep -ci "Present  : Yes" )
redundant=$(/sbin/hpasmcli -s "show powersupply" | grep -ci "Redundant: Yes" )
condition=$(/sbin/hpasmcli -s "show powersupply" | grep -ci "Condition: Ok" )

presentfile="/var/cache/$(basename $0 .sh)-present"
redundantfile="/var/cache/$(basename $0 .sh)-redundant"
conditionfile="/var/cache/$(basename $0 .sh)-condition"

function notify {
    local title=$1
    local message=$2
    local tag=$3
    curl -H "Title: $title" -H "Priority: high" -H "tags: $tag" -d "$message" "ntfy.sh/$NTFY_TOPIC"
}

function check_and_notify {
    local file=$1
    local value=$2
    local message=$3
    local time_diff=$(( $(date +%s) - $(date +%s -r "$file") ))

    if [[ ! -f "$file" || $time_diff -gt 3600 ]]; then
        if [[ $value -ne 2 ]]; then
            notify "HP Powersupply Status" "$message" "electric_plug,warning"
            touch "$file"
        fi
    fi

    if [[ -f "$file" ]]; then
        if [[ $value -eq 2 ]]; then
            notify "HP Powersupply Status" "$(echo "$message" | sed 's/ NOT//')" "electric_plug,white_check_mark"
            rm "$file"
        fi
    fi
}

check_and_notify "$presentfile" "$present" "Powersupply present NOT OK."
check_and_notify "$redundantfile" "$redundant" "Power NOT reduntant."
check_and_notify "$conditionfile" "$condition" "Power supply NOT OK."
