#!/usr/bin/env bash
# 24-diag-vendorboot.sh — แพ็ก vendor_boot-diag.img (initramfs diagnostics + console=ttyGS0)
#   bash 24-diag-vendorboot.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUNNY="${SUNNY_ROOT:-$HERE/..}"
OUT="$SUNNY/out"
MK="$SUNNY/tools/mkbootimg/mkbootimg.py"
[ -f "$OUT/initramfs-diag.cpio.gz" ] || { echo "ต้องมี initramfs-diag — รัน 04-diag-initramfs.sh"; exit 1; }
[ -f "$OUT/dtb" ] || { echo "ต้องมี dtb"; exit 1; }

CMDLINE="console=ttyGS0,115200n8 ignore_loglevel nowatchdog androidboot.hardware=qcom \
androidboot.usbcontroller=a600000.dwc3 loop.max_part=7 lpm_levels.sleep_disabled=1 \
service_locator.enable=1 swiotlb=1 msm_rtb.filter=0x237 kpti=off"

python3 "$MK" --header_version 4 \
  --vendor_boot "$OUT/vendor_boot-diag.img" \
  --vendor_ramdisk "$OUT/initramfs-diag.cpio.gz" \
  --dtb "$OUT/dtb" \
  --vendor_cmdline "$CMDLINE" \
  --os_version 16.0.0 --os_patch_level 2026-05 \
  --pagesize 4096

ls -lh "$OUT/vendor_boot-diag.img"
cp "$OUT/vendor_boot-diag.img" "$OUT/initramfs-diag.cpio.gz" \
  "/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out/" 2>/dev/null || true
sha256sum "$OUT/vendor_boot-diag.img"
echo "เสร็จ: vendor_boot-diag.img (โหมดวินิจฉัย: ไม่ switch_root + kernel log→ttyGS0)"
