#!/bin/sh
R=/sys/class/dual_role_usb/otg_default
echo 'waiting for computer to be unplugged'
n=0
while [ "$(cat "$R/mode" 2>/dev/null)" != none ] && [ "$n" -lt 120 ]; do sleep 1; n=$((n+1)); done
if [ "$n" -ge 120 ]; then echo 'timeout waiting for unplug'; exit 1; fi
echo 'waiting 10 seconds for keyboard connection'
sleep 10
echo 'request host/source mode'
echo dfp > "$R/mode" 2>&1
n=0
while [ "$n" -lt 30 ]; do
  echo "=== $n seconds ==="
  for f in mode data_role power_role; do printf '%s=' "$f"; cat "$R/$f" 2>&1; done
  printf 'typec='; cat /sys/class/power_supply/usb/typec_mode 2>&1
  cat /proc/bus/input/devices
  ls /sys/class/net
  /usr/bin/busybox dmesg | tail -25
  sleep 1; n=$((n+1))
done
echo 'restore device mode'
echo ufp > "$R/mode" 2>&1
echo 'probe complete'
sync
