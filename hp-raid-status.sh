#!/bin/bash

NTFY_TOPIC=$(hostname | sed 's/\./-/g')-$(dmidecode -t system | grep "Serial Number" | cut -d\  -f3)

diskstatus=$(hpssacli ctrl slot=0 show config detail | grep -ci "Status: Failed physical drive")
ctrlstatus=$(hpssacli ctrl slot=0 show config detail | grep -ci "Controller Status: OK")
cachestatus=$(hpssacli ctrl slot=0 show config detail | grep -ci "Cache Status: OK")
batstatus=$(hpssacli ctrl slot=0 show config detail | grep -ci "Battery/Capacitor Status: OK")

if [ $diskstatus -eq 1 ]; then curl -H "Title: HP RAID Status" -H "Priority: high" -H "tags: computer,skull" -d "One or more physical disks have failed." ntfy.sh/$NTFY_TOPIC ; fi
if [ $ctrlstatus -ne 1 ]; then curl -H "Title: HP RAID Status" -H "Priority: high" -H "tags: computer,skull" -d "Controller Status NOT OK." ntfy.sh/$NTFY_TOPIC ; fi
if [ $cachestatus -ne 1 ]; then curl -H "Title: HP RAID Status" -H "Priority: high" -H "tags: computer,skull" -d "Cache Status NOT OK" ntfy.sh/$NTFY_TOPIC ; fi 
if [ $batstatus -ne 1 ]; then curl -H "Title: HP RAID Status" -H "Priority: high" -H "tags: computer,skull" -d "Battery/Capacitor Status NOT OK." ntfy.sh/$NTFY_TOPIC; fi
