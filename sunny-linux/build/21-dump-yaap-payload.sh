#!/usr/bin/env bash
# 21-dump-yaap-payload.sh — หยอด boot/vendor_boot/dtbo/vbmeta จาก YAAP OTA (payload.bin)
#   bash 21-dump-yaap-payload.sh [<yaap.zip ใน WSL>]
set -euo pipefail
ZIP="${1:-${SUNNY_ROOT:-/root/sunny}/stock/yaap.zip}"
OUT="${SUNNY_ROOT:-/root/sunny}/stock/payload_out"
PDG="${SUNNY_ROOT:-/root/sunny}/tools/payload-dumper-go/payload-dumper-go"
[ -f "$ZIP" ] || { echo "ไม่พบ $ZIP"; exit 1; }
mkdir -p "$OUT"
cd "$OUT"

# 1) ดึง payload.bin ออกจาก zip (แตกเฉพาะไฟล์นี้ เก็บส่วนที่เหลือไว้ไม่ต้องแตก)
if [ ! -s payload.bin ]; then
  echo "==> แตก payload.bin จาก zip"
  unzip -o "$ZIP" payload.bin -d "$OUT" >/dev/null
fi
ls -lh payload.bin

# 2) หยอดเฉพาะพาร์ติที่ต้องการ (go dumper รุ่น 2.x รองรับ zstd/zucchini)
"$PDG" -partitions boot,vendor_boot,dtbo,vbmeta -o "$OUT" payload.bin

echo "== ผลลัพธ์ =="
ls -lh "$OUT"/*.img
