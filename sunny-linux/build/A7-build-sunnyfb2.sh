#!/usr/bin/env bash
# A7-build-sunnyfb2.sh — compile + base64 the geometry probe
set -u
S="/mnt/c/Users/brown/Documents/Default Project/sunny-linux/src"
OUT=/root/sunny/out
W="/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out"
mkdir -p "$OUT"
cd "$S" || exit 1

aarch64-linux-gnu-gcc -Os -static -nostdlib -ffreestanding \
  -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables \
  -I/usr/include/libdrm -Wl,--build-id=none -o "$OUT/sunnyfb2" sunnyfb2.c 2>&1 | head -30

if [ ! -f "$OUT/sunnyfb2" ]; then echo "BUILD FAILED"; exit 1; fi
ls -l "$OUT/sunnyfb2"
sha256sum "$OUT/sunnyfb2"
base64 -w 76 "$OUT/sunnyfb2" > "$OUT/sunnyfb2.b64"
cp -f "$OUT/sunnyfb2.b64" "$W/sunnyfb2.b64"
wc -c "$OUT/sunnyfb2.b64"
