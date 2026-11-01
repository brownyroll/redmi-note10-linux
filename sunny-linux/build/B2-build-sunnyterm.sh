#!/usr/bin/env bash
# B2-build-sunnyterm.sh
set -u
S="/mnt/c/Users/brown/Documents/Default Project/sunny-linux/src"
OUT=/root/sunny/out
W="/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out"
cd "$S" || exit 1
aarch64-linux-gnu-gcc -Os -static -nostdlib -ffreestanding \
  -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables \
  -I/usr/include/libdrm -Wl,--build-id=none -o "$OUT/sunnyterm" sunnyterm.c 2>&1 | head -40
[ -f "$OUT/sunnyterm" ] || { echo "BUILD FAILED"; exit 1; }
ls -l "$OUT/sunnyterm"
sha256sum "$OUT/sunnyterm"
base64 -w 76 "$OUT/sunnyterm" > "$OUT/sunnyterm.b64"
cp -f "$OUT/sunnyterm.b64" "$W/sunnyterm.b64"
wc -c "$OUT/sunnyterm.b64"
