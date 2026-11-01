#!/usr/bin/env bash
# 98-pack-fbcon-boot.sh — แพ็ก boot.img จาก Image.fbcon (kernel ที่มี fbdev console)
set -eu
SUNNY=/root/sunny
OUT=$SUNNY/out
W="/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out"
MK=$SUNNY/tools/mkbootimg/mkbootimg.py
BASE=0x00000000; KERNEL_OFF=0x00008000; RAMDISK_OFF=0x01000000; TAGS_OFF=0x00000100; PAGESIZE=4096
CMDLINE="console=tty0 console=ttyMSM0,115200n8 androidboot.hardware=qcom androidboot.usbcontroller=a600000.dwc3 loop.max_part=7 lpm_levels.sleep_disabled=1 service_locator.enable=1 swiotlb=1 msm_rtb.filter=0x237 kpti=off"

[ -f "$OUT/Image.fbcon" ] || { echo "missing Image.fbcon"; exit 1; }

python3 "$MK" --header_version 4 \
  --kernel "$OUT/Image.fbcon" \
  --cmdline "$CMDLINE" \
  --base "$BASE" --kernel_offset "$KERNEL_OFF" --ramdisk_offset "$RAMDISK_OFF" \
  --tags_offset "$TAGS_OFF" --pagesize "$PAGESIZE" \
  --os_version 16.0.0 --os_patch_level 2026-05 \
  -o "$OUT/boot-fbcon.img"

cp -f "$OUT/boot-fbcon.img" "$W/boot-fbcon.img"
ls -lh "$OUT/boot-fbcon.img" "$W/boot-fbcon.img"
sha256sum "$OUT/boot-fbcon.img"
echo "--- มี vendor_boot ให้ใช้ ---"
ls -lh "$W"/vendor_boot-*.img 2>/dev/null
