#!/usr/bin/env bash
# 41-inspect-rootfs.sh — ดูว่า rootfs ใน image มีอะไรบ้าง (ก่อนติดตั้ง sunny-init)
set -u
SUNNY="${SUNNY_ROOT:-/root/sunny}"
OUT="$SUNNY/out"
M="$SUNNY/mnt-root"
mkdir -p "$M"
mountpoint -q "$M" || mount -o loop,rw "$OUT/rootfs.img" "$M" || { echo "mount fail"; exit 1; }
echo "== root listing =="
ls "$M"
echo "== binaries =="
for f in bin/sh bin/bash usr/sbin/sshd usr/bin/ssh-keygen sbin/ip usr/sbin/ip bin/ip sbin/ifconfig bin/ifconfig usr/bin/getty sbin/getty usr/bin/busybox bin/busybox sbin/agetty usr/sbin/agetty; do
  if [ -e "$M/$f" ]; then echo "OK   $f -> $(readlink -f "$M/$f" | sed "s|$M||")"; else echo "--   $f"; fi
done
echo "== ssh ==="
ls "$M/etc/ssh" 2>/dev/null | head
echo "== users =="
grep -E '^(dev|root):' "$M/etc/passwd" 2>/dev/null
echo "== fstab =="
cat "$M/etc/fstab" 2>/dev/null | head
echo "== hostname =="
cat "$M/etc/hostname" 2>/dev/null
echo "== lib systemd =="
ls "$M/lib/systemd/systemd" 2>/dev/null
echo "== init dir =="
ls "$M/sbin" | head -20
