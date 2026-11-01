#!/usr/bin/env bash
# A3-pack-fbcon-nocmd.sh — boot.img จาก Image.fbcon แต่ cmdline ว่าง (เหมือน YAAP ที่บูตได้)
# เพื่อแยกตัวแปร: ถ้า bootloop = ปัญหาอยู่ที่ kernel ของเรา ไม่ใช่ cmdline/fbcon
set -eu
OUT=/root/sunny/out
W="/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out"
MK=/root/sunny/tools/mkbootimg/mkbootimg.py

[ -f "$OUT/Image.fbcon" ] || { echo "missing Image.fbcon"; exit 1; }

python3 "$MK" --header_version 4 \
  --kernel "$OUT/Image.fbcon" \
  --cmdline "" \
  --base 0x00000000 --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --tags_offset 0x00000100 --pagesize 4096 \
  --os_version 16.0.0 --os_patch_level 2026-05 \
  -o "$OUT/boot-fbcon-nocmd.img"

cp -f "$OUT/boot-fbcon-nocmd.img" "$W/boot-fbcon-nocmd.img"
ls -l "$OUT/boot-fbcon-nocmd.img" "$W/boot-fbcon-nocmd.img"
echo "--- embedded version string in our kernel ---"
strings -a "$OUT/Image.fbcon" | grep -m3 -E '^Linux version 4\.14' || echo "(no version string)"
