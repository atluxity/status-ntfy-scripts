#!/bin/bash
NTFY_TOPIC=$(hostname | sed 's/\./-/g')-$(dmidecode -t system | grep "Serial Number" | cut -d\  -f3)

present=$(hpasmcli -s "show powersupply" | grep -ci "Present  : Yes" )
redundant=$(hpasmcli -s "show powersupply" | grep -ci "Redundant: Yes" )
condition=$(hpasmcli -s "show powersupply" | grep -ci "Condition: Ok" )

if [ $present -ne 2 ]; then curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,warning" -d "Power supply missing." ntfy.sh/$NTFY_TOPIC ; fi
if [ $redundant -ne 2 ]; then curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,warning" -d "Power not redundant." ntfy.sh/$NTFY_TOPIC ; fi
if [ $condition -ne 2 ]; then curl -H "Title: HP Powersupply Status" -H "Priority: high" -H "tags: electric_plug,warning" -d "Power supply NOT OK." ntfy.sh/$NTFY_TOPIC ; fi 
