ls /sys/class/drm/
echo "-- status --"
for d in /sys/class/drm/card0-*; do
  echo "$d status=$(cat $d/status) enabled=$(cat $d/enabled)"
done
echo "-- debugfs --"
mount -t debugfs none /sys/kernel/debug 2>/dev/null
ls /sys/kernel/debug/dri/0/ 2>&1 | head
