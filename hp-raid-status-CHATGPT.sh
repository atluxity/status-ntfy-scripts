#!/bin/bash

NTFY_TOPIC=$(hostname | sed 's/\./-/g')-$(/sbin/dmidecode -t system | grep "Serial Number" | cut -d\  -f3)

diskstatus=$(/sbin/hpssacli ctrl slot=0 show config detail | grep -ci "Status: Failed physical drive")
ctrlstatus=$(/sbin/hpssacli ctrl slot=0 show config detail | grep -ci "Controller Status: OK")
cachestatus=$(/sbin/hpssacli ctrl slot=0 show config detail | grep -ci "Cache Status: OK")
batstatus=$(/sbin/hpssacli ctrl slot=0 show config detail | grep -ci "Battery/Capacitor Status: OK")

diskfile="/var/cache/$(basename $0 .sh)-present"
ctrlfile="/var/cache/$(basename $0 .sh)-redundant"
cachefile="/var/cache/$(basename $0 .sh)-condition"
batfile="/var/cache/$(basename $0 .sh)-battery"

function send_alert() {
  local title="$1"
  local message="$2"
  local icon="$3"
  curl -H "Title: $title" -H "Priority: high" -H "tags: computer,$icon" -d "$message" ntfy.sh/$NTFY_TOPIC
}

function check_disk_status() {
  if [ $diskstatus -eq 1 ]; then
    send_alert "HP RAID Status" "One or more physical disks have failed." skull
    touch $diskfile
  elif [ -f $diskfile ]; then
    send_alert "HP RAID Status" "Physical disks OK." white_check_mark
    rm $diskfile
  fi
}

function check_controller_status() {
  if [ $ctrlstatus -ne 1 ]; then
    send_alert "HP RAID Status" "Controller Status NOT OK." skull
    touch $ctrlfile
  elif [ -f $ctrlfile ]; then
    send_alert "HP RAID Status" "Controller Status OK." white_check_mark
    rm $ctrlfile
  fi
}

function check_cache_status() {
  if [ $cachestatus -ne 1 ]; then
    send_alert "HP RAID Status" "Cache Status NOT OK" skull
    touch $cachefile
  elif [ -f $cachefile ]; then
    send_alert "HP RAID Status" "Cache Status OK." white_check_mark
    rm $cachefile
  fi
}

function check_battery_status() {
  if [ $batstatus -ne 1 ]; then
    send_alert "HP RAID Status" "Battery/Capacitor Status NOT OK." skull
    touch $batfile
  elif [ -f $batfile ]; then
    send_alert "HP RAID Status" "Battery/Capacitor Status OK." white_check_mark
    rm $batfile
  fi
}

check_disk_status
check_controller_status
check_cache_status
check_battery_status

