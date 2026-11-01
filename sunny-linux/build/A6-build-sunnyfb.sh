#!/usr/bin/env bash
# A6-build-sunnyfb.sh — cross-compile the tiny static DRM test binary
set -u
S="/mnt/c/Users/brown/Documents/Default Project/sunny-linux/src"
OUT=/root/sunny/out
mkdir -p "$OUT"
cd "$S" || exit 1

aarch64-linux-gnu-gcc -Os -static -nostdlib -ffreestanding \
  -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables \
  -I/usr/include/libdrm -Wl,--build-id=none -o "$OUT/sunnyfb" sunnyfb.c 2>&1 | head -40

if [ -f "$OUT/sunnyfb" ]; then
  ls -l "$OUT/sunnyfb"
  file "$OUT/sunnyfb"
  aarch64-linux-gnu-readelf -h "$OUT/sunnyfb" | head -12
  ls -l "$OUT/sunnyfb"
  echo "b64 size: $(( $(stat -c%s "$OUT/sunnyfb") * 4 / 3 + 4 ))"
  base64 -w 76 "$OUT/sunnyfb" > "$OUT/sunnyfb.b64"
  wc -l "$OUT/sunnyfb.b64"
else
  echo "BUILD FAILED"
fi
