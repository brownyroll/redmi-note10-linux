busybox --list 2>/dev/null | grep -E '^(base64|uudecode|sha256sum|xxd|od)$'
echo "-- free space /tmp --"
df -h /tmp 2>/dev/null | tail -2
