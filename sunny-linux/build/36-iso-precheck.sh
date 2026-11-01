#!/usr/bin/env bash
# 36-iso-precheck.sh — เช็คของที่ script จะใช้: openssh ใน squashfs, qemu, mke2fs, rsync, img2simg, mkbootimg
set -uo pipefail
SQQ=/root/sunny/iso/sq

echo "=== openssh ใน squashfs? ==="
ls "$SQQ/usr/sbin/sshd" 2>/dev/null && echo "มี sshd ✓" || echo "ไม่มี sshd"
ls "$SQQ/usr/bin/ssh" 2>/dev/null && echo "มี ssh client ✓" || echo "ไม่มี ssh client"

echo "=== ระบบ systemd ใน squashfs ==="
ls "$SQQ/lib/systemd/systemd" "$SQQ/usr/lib/systemd/systemd" 2>/dev/null | head -3

echo "=== networkd / netplan ==="
ls "$SQQ/lib/systemd/systemd-networkd" "$SQQ/usr/lib/systemd/systemd-networkd" 2>/dev/null | head -2

echo "=== ขนาดโดยรวมของโฟลเดอร์จำเป็น ==="
du -sh "$SQQ/usr" "$SQQ/lib" "$SQQ/var" "$SQQ/boot" 2>/dev/null
echo "=== modules 7.0 (จะลบทิ้ง) ==="
du -sh "$SQQ/usr/lib/modules" 2>/dev/null
du -sh "$SQQ/usr/lib/firmware" 2>/dev/null

echo "=== tools ใน WSL ==="
for t in qemu-aarch64-static mke2fs e2fsck rsync img2simg python3 cpio gzip; do
  command -v "$t" >/dev/null 2>&1 && echo "$t ✓" || echo "$t ✗ (ขาด)"
done

echo "=== mkbootimg / dtb / YAAP kernel ที่มีอยู่ ==="
ls -lh /root/sunny/tools/mkbootimg/mkbootimg.py /root/sunny/out/dtb /root/sunny/out/boot-yaap-k.img /root/sunny/out/Image-yaap 2>/dev/null

echo "=== initramfs-diag ที่ล่าสุด ==="
ls -lh /root/sunny/out/initramfs-diag.cpio.gz /root/sunny/out/initramfs.cpio.gz 2>/dev/null
