#!/usr/bin/env bash
# 20-get-busybox-aarch64.sh — ดาวน์โหลด busybox-static arm64 (aarch64) จาก Ubuntu Ports
#   ทำแยกเพื่อ debug การแพีส index และจะถูก 04-initramfs.sh เรียกใช้ผลลัพธ์
set -euo pipefail
OUT="${SUNNY_ROOT:-/root/sunny}/out"
[ -d "$OUT" ] || { echo "ไม่พบ $OUT — รองรับ SUNNY_ROOT หรือ mkdir ก่อน"; exit 1; }

cd "$OUT"
rm -f Packages.gz busybox-static-arm64.deb
curl -sL --no-progress-meter -o Packages.gz \
  "http://ports.ubuntu.com/ubuntu-ports/dists/noble/main/binary-arm64/Packages.gz"
[ -s Packages.gz ] || { echo "ไม่ได้ Packages.gz"; exit 1; }
gunzip -f Packages.gz
grep -A20 '^Package: busybox-static$' Packages | head -25 || true
deb=$(grep -A20 '^Package: busybox-static$' Packages | awk '$1=="Filename:"{print $2; exit}')
[ -n "$deb" ] || { echo "ไม่พบ Filename" ; exit 1; }
echo "==> filename=$deb"
curl -L --no-progress-meter -o busybox-static-arm64.deb "http://ports.ubuntu.com/ubuntu-ports/$deb"
[ -s busybox-static-arm64.deb ] || { echo "ไฟล์ .deb ว่าง"; exit 1; }
rm -rf "$OUT/.bbx"
dpkg-deb -x busybox-static-arm64.deb "$OUT/.bbx"
cp "$OUT/.bbx/usr/bin/busybox" "$OUT/busybox-aarch64"
rm -rf "$OUT/.bbx"
file "$OUT/busybox-aarch64"
ls -lh "$OUT/busybox-aarch64" "$OUT/busybox-static-arm64.deb"
echo "เสร็จ: $OUT/busybox-aarch64 (ELF aarch64)"
