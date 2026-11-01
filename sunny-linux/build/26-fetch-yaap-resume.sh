#!/usr/bin/env bash
# 26-fetch-yaap-resume.sh — โหลด YAAP zip แบบ resume ซ้ำ ๆ จนเสร็จ + ตรวจ sha256
set -uo pipefail
cd /root/sunny/stock
URL='https://mirror.codebucket.de/yaap/sunny/YAAP-16-Banshee-sunny-20260505.zip'
SHA_URL='https://mirror.codebucket.de/yaap/sunny/YAAP-16-Banshee-sunny-20260505.zip.sha256sum'
ok=0
for i in $(seq 1 30); do
  curl -L --http1.1 --no-progress-meter -C - -o yaap.zip "$URL" && { ok=1; break; }
  code=$?
  echo "[try $i] curl exit=$code ขนาดปัจจุบัน=$(stat -c%s yaap.zip)"
  # error 416 = ไฟล์เกิน content-length อาจโหลดเสร็จแล้ว
  if [ "$code" = 33 ]; then ok=1; break; fi
  sleep 3
done
[ "$ok" = 1 ] || { echo "โหลดไม่สำเร็จหลัก 30 รอบ"; exit 1; }
ls -lh yaap.zip
echo "== ตรวจ sha256 =="
curl -sL "$SHA_URL" | sed 's/YAAP-16-Banshee-sunny-20260505.zip/yaap.zip/' | sha256sum -c
