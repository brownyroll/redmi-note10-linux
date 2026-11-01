#!/usr/bin/env bash
# patches.sh — แพตช์ซอร์ส kernel ให้คอมไพล์ด้วย GCC 13 (idempotent, รันซ้ำได้)
#   bash patches.sh
set -uo pipefail
SUNNY_ROOT="${SUNNY_ROOT:-/root/sunny}"
K="$SUNNY_ROOT/src/kernel"
[ -d "$K" ] || { echo "ไม่พบ kernel tree: $K"; exit 1; }
cd "$K"

echo "== patches =="

# ---------------------------------------------------------------- 1
# drivers/gpu/drm/drm_atomic.c อ้าง last_input_time (ตัวแปรของ cpu_input_boost)
# โดยไม่ include header — เป็น hack จาก Xiaomi ที่ cherry-pick มาไม่ครบ
F="drivers/gpu/drm/drm_atomic.c"
if grep -q 'last_input_time' "$F"; then
  sed -i 's/time_before(jiffies, last_input_time + msecs_to_jiffies(3000))/0/' "$F"
  echo "  [1] $F : ตัดเงื่อนไข last_input_time → 0"
else
  echo "  [1] $F : ไม่ต้องแพตช์แล้ว"
fi

echo "== เสร็จ (diff ที่แก้: git -C $K diff --stat) =="
git -C "$K" diff --stat 2>/dev/null | tail -5 || true
