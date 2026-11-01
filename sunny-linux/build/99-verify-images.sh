#!/usr/bin/env bash
# 99-verify-images.sh — ตรวจ boot/vendor_boot ที่แพ็กแล้ว + sha256
set -uo pipefail
OUT="${SUNNY_ROOT:-/root/sunny}/out"
MK="${SUNNY_ROOT:-/root/sunny}/tools/mkbootimg/unpack_bootimg.py"

for img in boot vendor_boot; do
  [ -f "$OUT/$img.img" ] || { echo "ไม่พบ $OUT/$img.img"; continue; }
  echo "== $img.img =="
  rm -rf "/tmp/u_$img"; mkdir -p "/tmp/u_$img"
  python3 "$MK" --boot_img "$OUT/$img.img" --out "/tmp/u_$img" 2>&1 | head -18
  echo "  payload: $(ls -l "/tmp/u_$img" | awk 'NR>1{printf "%s(%s) ", $9, $5}')"
  echo
done

echo "== sha256 =="
sha256sum "$OUT"/*.img 2>/dev/null || true
