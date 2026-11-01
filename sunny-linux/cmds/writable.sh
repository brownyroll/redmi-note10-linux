echo "-- root --"
ls -la /
echo "-- mounts --"
mount | head -10
echo "-- writable? --"
for d in /tmp /dev/shm /run /var/tmp /root /cache /home; do
  mkdir -p $d 2>/dev/null
  if touch $d/.wtest 2>/dev/null; then echo "OK  $d"; rm -f $d/.wtest; else echo "RO  $d"; fi
done
