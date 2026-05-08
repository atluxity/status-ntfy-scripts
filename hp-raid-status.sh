#!/bin/bash

NTFY_BASE_URL="${NTFY_BASE_URL:-https://ntfy.sh}"
if [ -z "${NTFY_TOPIC:-}" ]; then
	raw_ntfy_topic="$(hostname | sed 's/\./-/g')-$(/sbin/dmidecode -t system | grep "Serial Number" | cut -d\  -f3)"
	NTFY_TOPIC="$(printf '%s' "$raw_ntfy_topic" | tr '[:upper:]' '[:lower:]')"
fi
NTFY_URL="${NTFY_BASE_URL%/}/$NTFY_TOPIC"

diskstatus=$(/sbin/hpssacli ctrl slot=0 show config detail | grep -ci "Status: Failed physical drive")
ctrlstatus=$(/sbin/hpssacli ctrl slot=0 show config detail | grep -ci "Controller Status: OK")
cachestatus=$(/sbin/hpssacli ctrl slot=0 show config detail | grep -ci "Cache Status: OK")
batstatus=$(/sbin/hpssacli ctrl slot=0 show config detail | grep -ci "Battery/Capacitor Status: OK")

diskfile="/var/cache/$(basename $0 .sh)-present"
ctrlfile="/var/cache/$(basename $0 .sh)-redundant"
cachefile="/var/cache/$(basename $0 .sh)-condition"
batfile="/var/cache/$(basename $0 .sh)-battery"

if [ ! -f $diskfile ] || [ $(( $(date +%s) - $(date +%s -r $diskfile))) -gt 86400 ]; then
	if [ $diskstatus -eq 1 ]; then
		curl -H "Title: HP RAID Status" -H "Priority: high" -H "tags: computer,skull" -d "One or more physical disks have failed." "$NTFY_URL" &&
		touch $diskfile
	fi
fi

if [ ! -f $ctrlfile ] || [ $(( $(date +%s) - $(date +%s -r $ctrlfile))) -gt 86400 ]; then
	if [ $ctrlstatus -ne 1 ]; then
		curl -H "Title: HP RAID Status" -H "Priority: high" -H "tags: computer,skull" -d "Controller Status NOT OK." "$NTFY_URL" &&
		touch $ctrlfile
	fi
fi

if [ ! -f $cachefile ] || [ $(( $(date +%s) - $(date +%s -r $cachefile))) -gt 86400 ]; then
	if [ $cachestatus -ne 1 ]; then
		curl -H "Title: HP RAID Status" -H "Priority: high" -H "tags: computer,skull" -d "Cache Status NOT OK" "$NTFY_URL" &&
		touch $cachefile
	fi
fi

if [ ! -f $batfile ] || [ $(( $(date +%s) - $(date +%s -r $batfile))) -gt 86400 ]; then
	if [ $batstatus -ne 1 ]; then
		curl -H "Title: HP RAID Status" -H "Priority: high" -H "tags: computer,skull" -d "Battery/Capacitor Status NOT OK." "$NTFY_URL" &&
		touch $batfile
	fi
fi

if [ -f $diskfile ]; then
        if [ $diskstatus -eq 0 ]; then
                curl -H "Title: HP RAID Status" -H "Priority: high" -H "tags: computer,white_check_mark" -d "Physical disks OK." "$NTFY_URL" &&
                rm $diskfile
        fi
fi

if [ -f $ctrlfile ]; then
        if [ $ctrlstatus -eq 1 ]; then
                curl -H "Title: HP RAID Status" -H "Priority: high" -H "tags: computer,white_check_mark" -d "Controller Status OK." "$NTFY_URL" &&
                rm $ctrlfile
        fi
fi

if [ -f $cachefile ]; then
        if [ $cachestatus -eq 1 ]; then
                curl -H "Title: HP RAID Status" -H "Priority: high" -H "tags: computer,white_check_mark" -d "Cache Status OK" "$NTFY_URL" &&
                rm $cachefile
        fi
fi

if [ -f $batfile ]; then
        if [ $batstatus -eq 1 ]; then
                curl -H "Title: HP RAID Status" -H "Priority: high" -H "tags: computer,white_check_mark" -d "Battery/Capacitor Status OK." "$NTFY_URL" &&
                rm $batfile
        fi
fi
