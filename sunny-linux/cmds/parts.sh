echo "-- partitions (name/size in MB) --"
for b in /sys/class/block/sde*; do
  n=$(cat $b/uevent 2>/dev/null | grep PARTNAME | cut -d= -f2)
  [ -n "$n" ] && echo "$(basename $b) $n $(($(cat $b/size)*512/1024/1024))MB"
done
