#!/usr/bin/env bash
# 99-log-errors.sh — สรุป error จาก build log พร้อม context
#   bash 99-log-errors.sh [/root/sunny/out/build.log] [lines]
LOG="${1:-/root/sunny/out/build.log}"
CTX="${2:-4}"
[ -f "$LOG" ] || { echo "ไม่พบ $LOG"; exit 1; }

echo "== error lines =="
grep -nE '(^|[^a-z_])error:|Error [12]$|undefined reference|No rule to make' "$LOG" | tail -20

echo
echo "== context =="
grep -nE '(^|[^a-z_])error:' "$LOG" | tail -3 | cut -d: -f1 | while read -r n; do
  sed -n "$((n-CTX)),$((n+CTX))p" "$LOG"
  echo "-----"
done
