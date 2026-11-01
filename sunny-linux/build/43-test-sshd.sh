#!/usr/bin/env bash
# 43-test-sshd.sh — ทดสอบ sshd ของ rootfs image บน WSL ผ่าน qemu (port 2222)
set -u
SUNNY="${SUNNY_ROOT:-/root/sunny}"
OUT="$SUNNY/out"
M="$SUNNY/mnt-root"
mkdir -p "$M"
mountpoint -q "$M" || mount -o loop,rw "$OUT/rootfs.img" "$M" || exit 1
cp /usr/bin/qemu-aarch64-static "$M/qemu"
mkdir -p "$M/dev" "$M/proc" "$M/sys"
mountpoint -q "$M/dev"  || mount --bind /dev "$M/dev" 2>/dev/null
mountpoint -q "$M/proc" || mount -t proc proc "$M/proc" 2>/dev/null
mountpoint -q "$M/sys"  || mount -t sysfs sysfs "$M/sys" 2>/dev/null
echo "START sshd on :2222"
exec chroot "$M" /qemu /usr/sbin/sshd -D -p 2222 -o PidFile=/tmp/sshd-test.pid
