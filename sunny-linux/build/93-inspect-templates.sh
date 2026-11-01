#!/usr/bin/env bash
set -u
cd /root/sunny/src/pmaports || exit 1
for d in device-xiaomi-monet device-xiaomi-begonia device-xiaomi-davinci device-xiaomi-vayu; do
  f="device/testing/$d/deviceinfo"
  [ -f "$f" ] || continue
  echo "===== $d ====="
  grep -vE '^\s*#' "$f" | sed '/^$/d' | head -40
  echo
done
echo "===== kernel packages with bundled config ====="
for p in device/*/linux-xiaomi-*; do
  n=$(basename "$p"); s=${n#linux-xiaomi-}
  for c in "$p"/config-xiaomi-*.aarch64 "$p"/config-*.aarch64; do
    [ -f "$c" ] && echo "$p -> $(basename "$c")"
  done
done 2>/dev/null | head -20
echo
echo "===== linux-xiaomi-monet APKBUILD ====="
sed -n '1,40p' device/testing/linux-xiaomi-monet/APKBUILD 2>/dev/null
