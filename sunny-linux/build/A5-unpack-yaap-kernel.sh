#!/usr/bin/env bash
set -u
O=/root/sunny/out
rm -rf /tmp/uyaap
python3 /root/sunny/tools/mkbootimg/unpack_bootimg.py --boot_img "$O/boot-yaap-k.img" --out /tmp/uyaap 2>&1 | head -8
echo "--- kernel ---"
ls -l /tmp/uyaap/kernel
xxd -l 64 /tmp/uyaap/kernel
file /tmp/uyaap/kernel
python3 - /tmp/uyaap/kernel <<'PY'
import sys, struct
d = open(sys.argv[1],'rb').read(0x40)
print("  magic:", hex(struct.unpack('<I', d[56:60])[0]))
PY
echo "--- gzip/lz4 magic check ---"
head -c 4 /tmp/uyaap/kernel | xxd
echo "--- md5 compare with ours ---"
md5sum /tmp/uyaap/kernel "$O/Image" "$O/Image.fbcon"
