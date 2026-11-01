#!/usr/bin/env bash
set -u
O=/root/sunny/out
for f in boot.img boot-fbcon.img; do
  echo "== $f"
  rm -rf "/tmp/u_$f"
  python3 /root/sunny/tools/mkbootimg/unpack_bootimg.py --boot_img "$O/$f" --out "/tmp/u_$f" 2>/dev/null | head -6
  head -c 200 "/tmp/u_$f/bootimg-cmdline" 2>/dev/null; echo
done
echo "--- kernels ---"
ls -l /tmp/u_boot.img/kernel /tmp/u_boot-fbcon.img/kernel 2>/dev/null
md5sum /tmp/u_boot.img/kernel /tmp/u_boot-fbcon.img/kernel 2>/dev/null
echo "--- images ---"
ls -l "$O"/Image "$O"/Image.fbcon "$O"/Image.prev 2>/dev/null
md5sum "$O"/Image "$O"/Image.fbcon "$O"/Image.prev 2>/dev/null
echo "--- config diff: prev vs now ---"
grep -c . "$O"/.config 2>/dev/null
