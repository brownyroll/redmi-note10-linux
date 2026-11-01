#!/usr/bin/env bash
# 39-vendorboot-real.sh — แพ็ก vendor_boot.img (จริงๆ: initramfs switch_root + dtb + cmdline YAAP-style)
#   ใช้ค่า header ให้ตรงกับ YAAP: os_version 16.0.0 / patch 2026-05, pagesize 4096
#   bash 39-vendorboot-real.sh
set -euo pipefail
ROOT="${SUNNY_ROOT:-/root/sunny}"
OUT="$ROOT/out"
MK="$ROOT/tools/mkbootimg/mkbootimg.py"

[ -f "$OUT/initramfs.cpio.gz" ] || { echo "ต้องมี initramfs — รัน 04-initramfs.sh (จะส่ง SUNNY_ROOT ให้)"; exit 1; }
[ -f "$OUT/dtb" ] || { echo "ต้องมี dtb — รัน 21-dump-yaap-payload.sh (+ unpack)"; exit 1; }

CMDLINE="console=tty0 console=ttyMSM0,115200n8 console=ttyGS0,115200n8 root=LABEL=sunny-root rw nowatchdog \
androidboot.hardware=qcom androidboot.usbcontroller=a600000.dwc3 loop.max_part=7 \
lpm_levels.sleep_disabled=1 service_locator.enable=1 swiotlb=1 msm_rtb.filter=0x237 kpti=off"

python3 "$MK" --header_version 4 \
  --vendor_boot "$OUT/vendor_boot.img" \
  --vendor_ramdisk "$OUT/initramfs.cpio.gz" \
  --dtb "$OUT/dtb" \
  --vendor_cmdline "$CMDLINE" \
  --os_version 16.0.0 --os_patch_level 2026-05 \
  --pagesize 4096

cp "$OUT/vendor_boot.img" "/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out/vendor_boot.img" 2>/dev/null || true
ls -lh "$OUT/vendor_boot.img"
sha256sum "$OUT/vendor_boot.img"
echo "เสร็จ: vendor_boot.img จริง (initramfs switch_root)"
