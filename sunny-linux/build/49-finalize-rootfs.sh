#!/usr/bin/env bash
# 49-finalize-rootfs.sh — unmount, ตรวจ fs, สร้าง sparse image, ก๊อปไป Windows
set -u
SUNNY="${SUNNY_ROOT:-/root/sunny}"
OUT="$SUNNY/out"
M="$SUNNY/mnt-root"
WIN="/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out"

pkill -f 'sshd-session' 2>/dev/null
pkill -f 'chroot' 2>/dev/null
sleep 1
for m in dev proc sys; do umount -l "$M/$m" 2>/dev/null || true; done
umount "$M" 2>/dev/null || umount -l "$M" 2>/dev/null || true
rm -f "$M/qemu"

echo "==> e2fsck"
e2fsck -fy "$OUT/rootfs.img" 2>&1 | tail -3

echo "==> img2simg"
img2simg "$OUT/rootfs.img" "$OUT/rootfs.simg"

cp "$OUT/rootfs.simg" "$WIN/rootfs.simg"
ls -lh "$OUT/rootfs.img" "$OUT/rootfs.simg" "$WIN/rootfs.simg"
sha256sum "$OUT/rootfs.simg" | tee "$OUT/rootfs.simg.sha256"
echo "เสร็จ: rootfs.simg พร้อมแฟลช"
