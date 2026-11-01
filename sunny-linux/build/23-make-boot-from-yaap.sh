#!/usr/bin/env bash
# 23-make-boot-from-yaap.sh — แพ็ก kernel ของ YAAP (ที่พิสูจน์ว่าบูตได้) กับ header ต่างของมันเอง
#   ใช้ kernel YAAP + generic ramdisk ว่าง + cmdline ของ YAAP → boot.img ทดสอบ
#   bash 23-make-boot-from-yaap.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUNNY="${SUNNY_ROOT:-/root/sunny}"
OUT="$SUNNY/out"
STOCK="$SUNNY/stock/payload_out"
MK="$SUNNY/tools/mkbootimg/mkbootimg.py"
UNPACK="$SUNNY/tools/mkbootimg/unpack_bootimg.py"
YB="$STOCK/boot.img"
[ -f "$YB" ] || { echo "ไม่พบ $YB — รอ 21-dump-yaap-payload.sh ก่อน"; exit 1; }

# 1) unpack YAAP boot.img → ได้ kernel จริง + ค่า header
YU="$STOCK/yaap_boot_unpack"
rm -rf "$YU"; mkdir -p "$YU"
python3 "$UNPACK" --boot_img "$YB" --out "$YU" || true
echo "== ไฟล์ที่ unpack ได้ =="
find "$YU" -type f | sort

# 2) อ่าน header เป็นรายค่า (botheader.py)
python3 "$HERE/botheader.py" "$YB"

# 3) หา kernel file ที่ unpack สร้าง
KERNEL_YAAP=$(find "$YU" -maxdepth 2 -type f \( -name 'kernel*' -o -name 'boot-image*' \) | head -1)
[ -n "$KERNEL_YAAP" ] || { echo "ไม่พบ kernel ที่แตกออก"; exit 1; }
echo "== kernel YAAP =="; ls -lh "$KERNEL_YAAP"
file "$KERNEL_YAAP" || true

# 4) แพ็ก boot.img ทดสอบ: kernel YAAP + cmdline เดิมของ YAAP, header v4
#    (os_version/patch รับจาก env ปรับได้)
OSV="${BOOTIMG_OS_VERSION:-16.0.0}"
PATCH="${BOOTIMG_OS_PATCH:-2026-05-05}"
python3 "$MK" --header_version 4 \
  --kernel "$KERNEL_YAAP" \
  --os_version "$OSV" --os_patch_level "$PATCH" \
  --cmdline "${BOOTIMG_CMDLINE:-}" \
  -o "$OUT/boot-yaap-k.img"

# 5) ถ้า YAAP แตกรามดิสออกมาด้วย เผื่อใช้เทียบ (ไม่ใส่ใน boot-img เรา)
echo "== เทียบขนาด header ระหว่าง YAAP ต้นฉบับ กับ boot-yaap-k.img ที่สร้าง =="
ls -l "$YB" "$OUT/boot-yaap-k.img"
echo "เสร็จ: $OUT/boot-yaap-k.img"
