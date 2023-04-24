#!/bin/bash

NTFY_TOPIC=$(hostname | sed 's/\./-/g')-$(/sbin/dmidecode -t system | grep "Serial Number" | cut -d\  -f3)

present=$(/sbin/hpasmcli -s "show powersupply" | grep -ci "Present  : Yes" )
redundant=$(/sbin/hpasmcli -s "show powersupply" | grep -ci "Redundant: Yes" )
condition=$(/sbin/hpasmcli -s "show powersupply" | grep -ci "Condition: Ok" )

presentfile="/var/cache/$(basename $0 .sh)-present"
redundantfile="/var/cache/$(basename $0 .sh)-redundant"
conditionfile="/var/cache/$(basename $0 .sh)-condition"


if [ ! -f $presentfile ] || [$(( $(date +%s) - $(date +%s -r $presentfile))) -gt 3600]; then
	if [ $present -ne 2 ]; then
		curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,warning" -d "Powersupply missing." ntfy.sh/$NTFY_TOPIC &&
		touch $presentfile
	fi
fi

if [ ! -f $redundantfile ] || [$(( $(date +%s) - $(date +%s -r $redundantfile))) -gt 3600]; then
	if [ $redundant -ne 2 ]; then
		curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,warning" -d "Power not redundant." ntfy.sh/$NTFY_TOPIC && 
		touch $redundantfile
	fi
fi

if [ ! -f $conditionfile ] || [$(( $(date +%s) - $(date +%s -r $conditionfile))) -gt 3600]; then
	if [ $condition -ne 2 ]; then 
		curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,warning" -d "Power supply NOT OK." ntfy.sh/$NTFY_TOPIC &&
		touch $conditionfile 
	fi 
fi

if [ -f $presentfile ]; then
        if [ $present -eq 2 ]; then
                curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,white_check_mark" -d "2 Powersupplies present." ntfy.sh/$NTFY_TOPIC &&
                rm $presentfile 
        fi 
fi

if [ -f $redundantfile ]; then
        if [ $redundant -eq 2 ]; then
                curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,white_check_mark" -d "Power redundant." ntfy.sh/$NTFY_TOPIC &&
                rm $redundantfile
        fi
fi

if [ -f $conditionfile ]; then
        if [ $condition -eq 2 ]; then
                curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,white_check_mark" -d "Both powersupplies OK." ntfy.sh/$NTFY_TOPIC &&
                rm $conditionfile
        fi
fi

