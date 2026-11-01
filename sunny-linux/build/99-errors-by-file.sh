#!/usr/bin/env bash
# 99-errors-by-file.sh — สรุปไฟล์ที่คอมไพล์ไม่ผ่าน (ไม่ซ้ำ)
LOG="${1:-/root/sunny/out/build.log}"
echo "== ไฟล์ที่มี error =="
grep -E '(^|[^a-z_])error:' "$LOG" | cut -d: -f1 | sort | uniq -c | sort -rn | head -20
echo
echo "== ตัวอย่าง error แรกของแต่ละไฟล์ =="
grep -E '(^|[^a-z_])error:' "$LOG" | cut -d: -f1 | sort -u | while read -r f; do
  grep -m1 -E '(^|[^a-z_])error:' "$LOG" | grep -F "$f:" || true
done
