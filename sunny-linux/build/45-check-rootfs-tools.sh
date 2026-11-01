#!/usr/bin/env bash
# 45-check-rootfs-tools.sh — เช็คว่า sunny-init เรียกใช้คำสั่งที่มีอยู่จริงใน rootfs
set -u
SUNNY="${SUNNY_ROOT:-/root/sunny}"
M="$SUNNY/mnt-root"
mkdir -p "$M"
mountpoint -q "$M" || mount -o loop,ro "$SUNNY/out/rootfs.img" "$M" || exit 1
for f in /usr/sbin/sshd /usr/bin/ssh-keygen /usr/bin/ip /usr/bin/mountpoint /usr/bin/setsid /sbin/agetty /usr/sbin/agetty /usr/bin/hostname /usr/bin/logger /sbin/sunny-init; do
  if [ -e "$M$f" ]; then echo "OK   $f"; else echo "--   $f"; fi
done
echo "== passwd =="
grep -E '^(sshd|dev|root):' "$M/etc/passwd"
echo "== group sshd =="
grep -E '^sshd:' "$M/etc/group"
echo "== sftp-server =="
ls "$M"/usr/lib/openssh/sftp-server 2>/dev/null || ls "$M"/usr/lib/ssh/sftp-server 2>/dev/null
echo "== sunny-init syntax (busybox sh ของ rootfs) =="
sh -n "$M/sbin/sunny-init" 2>&1 | head -5 || true
umount "$M" 2>/dev/null || true
