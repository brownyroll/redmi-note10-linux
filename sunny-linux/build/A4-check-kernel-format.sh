#!/usr/bin/env bash
set -u
O=/root/sunny/out
echo "=== YAAP kernel (proven) ==="
ls -l /tmp/u_boot.img/kernel
xxd -l 64 /tmp/u_boot.img/kernel
file /tmp/u_boot.img/kernel 2>/dev/null
echo
echo "=== our Image (prev) ==="
ls -l "$O/Image.prev"
xxd -l 64 "$O/Image.prev"
echo
echo "=== our Image.fbcon ==="
xxd -l 32 "$O/Image.fbcon"
echo
echo "=== arm64 Image header (text_offset/magic) ==="
for f in /tmp/u_boot.img/kernel "$O/Image.fbcon"; do
  echo "-- $f"
  python3 - "$f" <<'PY'
import sys, struct
d = open(sys.argv[1],'rb').read(0x40)
code0, code1 = struct.unpack('<II', d[0:8])
text_offset, image_size, flags = struct.unpack('<QQQ', d[8:32])
magic = struct.unpack('<I', d[56:60])[0]
print(f"  code0={code0:#x} code1={code1:#x} text_offset={text_offset:#x} image_size={image_size:#x} flags={flags:#x} magic={magic:#x} (ARM64={magic==0x644d5241:#x})")
PY
done
