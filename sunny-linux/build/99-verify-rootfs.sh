#!/usr/bin/env bash
# 99-verify-rootfs.sh — ตรวจ rootfs.img ว่าได้ของครบก่อนแฟลช
set -uo pipefail
OUT="${SUNNY_ROOT:-/root/sunny}/out"
IMG="$OUT/rootfs.img"
[ -f "$IMG" ] || { echo "ไม่พบ $IMG"; exit 1; }

echo "== image =="
ls -lh "$IMG"
dumpe2fs -h "$IMG" 2>/dev/null | grep -E 'Filesystem volume name|Block count|Block size|Filesystem features' | head -5

echo "== ไฟล์สำคัญ (debugfs) =="
for f in /lib/systemd/systemd /usr/sbin/sshd /etc/ssh/sshd_config /etc/fstab \
         /etc/systemd/system/multi-user.target.wants/ssh.service \
         /etc/systemd/network/10-usb0.network /etc/passwd; do
  if debugfs -R "stat $f" "$IMG" 2>/dev/null | grep -q '^Inode:'; then echo "  ✓ $f"; else echo "  ✗ $f  <<< หาย"; fi
done

echo "== passwd (user dev?) =="
debugfs -R "cat /etc/passwd" "$IMG" 2>/dev/null | grep -E '^(dev|root):' || echo "  ไม่พบ user dev"

echo "== fstab =="
debugfs -R "cat /etc/fstab" "$IMG" 2>/dev/null

echo "== sshd drop-in =="
debugfs -R "cat /etc/ssh/sshd_config.d/99-sunny.conf" "$IMG" 2>/dev/null
