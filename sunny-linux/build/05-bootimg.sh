#!/usr/bin/env bash
# 05-bootimg.sh — แพ็ก boot.img (kernel, header v3) + vendor_boot.img (ramdisk, header v4)
#   sunny มีพาร์ทิชัน vendor_boot → ramdisk ต้องอยู่ที่นั่น ไม่ใช่ใน boot
#   bash 05-bootimg.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
OUT="$ROOT/out"

# ค่าเริ่มต้นของ SM6150/sunny (ตรวจทับได้ถ้ามี boot stock ให้ unpack)
BASE=0x00000000
KERNEL_OFF=0x00008000
RAMDISK_OFF=0x01000000
TAGS_OFF=0x00000100
PAGESIZE=4096
BOOT_HDR=4   # BoardConfig.mk ของ sunny: BOARD_BOOT_HEADER_VERSION := 4
CMDLINE="console=ttyMSM0,115200n8 loglevel=7 root=LABEL=sunny-root rw \
androidboot.hardware=qcom androidboot.usbcontroller=a600000.dwc3 \
loop.max_part=7 lpm_levels.sleep_disabled=1 service_locator.enable=1 \
swiotlb=1 msm_rtb.filter=0x237 kpti=off"
OSVER=11.0.0
PATCH=2021-01

# ถ้ามี boot stock ที่สำรองไว้ → ดึงของจริงมาใช้
STOCK=$(ls -1 "$ROOT"/logs/backup_*/boot_a.img 2>/dev/null | head -1 || true)
if [ -n "${STOCK:-}" ]; then
  echo "==> พบ stock boot: $STOCK"
  if command -v unpack_bootimg >/dev/null 2>&1; then
    unpack_bootimg --boot_img "$STOCK" --out "$OUT/stock_unpacked" 2>/dev/null | tee "$OUT/stock_boot_header.txt" || true
    echo "    (ดู $OUT/stock_boot_header.txt เพื่อยืนยัน base/offset/pagesize)"
  fi
fi

MKBOOTIMG=$(command -v mkbootimg || true)
[ -n "$MKBOOTIMG" ] || MKBOOTIMG="python3 $ROOT/tools/mkbootimg/mkbootimg.py"

[ -f "$OUT/Image" ]         || { echo "ยังไม่มี $OUT/Image — รัน 02-kernel.sh"; exit 1; }
[ -f "$OUT/initramfs.cpio.gz" ] || { echo "ยังไม่มี initramfs — รัน 04-initramfs.sh"; exit 1; }

COMMON=(--base "$BASE" --kernel_offset "$KERNEL_OFF" --ramdisk_offset "$RAMDISK_OFF"
        --tags_offset "$TAGS_OFF" --pagesize "$PAGESIZE"
        --os_version "$OSVER" --os_patch_level "$PATCH")

echo "==> boot.img (header v$BOOT_HDR, kernel เท่านั้น)"
$MKBOOTIMG --header_version "$BOOT_HDR" --kernel "$OUT/Image" --cmdline "$CMDLINE" \
  "${COMMON[@]}" -o "$OUT/boot.img"

echo "==> vendor_boot.img (header v$BOOT_HDR, ramdisk + dtb)"
DTBARG=()
[ -f "$OUT/dtb" ] && DTBARG=(--dtb "$OUT/dtb")
$MKBOOTIMG --header_version "$BOOT_HDR" --vendor_boot "$OUT/vendor_boot.img" \
  --vendor_ramdisk "$OUT/initramfs.cpio.gz" "${DTBARG[@]}" \
  --vendor_cmdline "$CMDLINE" "${COMMON[@]}"

echo
ls -lh "$OUT/boot.img" "$OUT/vendor_boot.img"
echo
echo "ถ้า unpack_bootimg ของ stock บอกค่าต่างจากนี้ ให้แก้ตัวแปรต้นไฟล์แล้วรันใหม่:"
echo "  base=$BASE kernel_offset=$KERNEL_OFF ramdisk_offset=$RAMDISK_OFF tags_offset=$TAGS_OFF pagesize=$PAGESIZE"
