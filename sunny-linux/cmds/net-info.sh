echo "-- link --"
ip -s link show rndis0 | head -6
echo "-- ping gw --"
ping -c 2 -W 2 192.168.42.1 2>&1 | tail -4
echo "-- listening tcp --"
cat /proc/net/tcp 2>/dev/null | head -5
echo "-- processes --"
ps w 2>/dev/null | head -20
