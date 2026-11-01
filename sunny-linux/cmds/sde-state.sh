echo "-- sde/dsi dmesg tail --"
dmesg | grep -iE 'sde|dsi|mdss|drm' | tail -15
echo "-- drm state (if any) --"
ls /sys/kernel/debug/dri/0/ 2>&1 | head
echo "-- crtc info --"
for f in /sys/kernel/debug/dri/0/*/ ; do echo "$f"; done 2>/dev/null
