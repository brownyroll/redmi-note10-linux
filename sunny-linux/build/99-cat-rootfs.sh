#!/usr/bin/env bash
# 99-cat-rootfs.sh — cat ไฟล์ใน rootfs.img
#   bash 99-cat-rootfs.sh /etc/fstab [path2 ...]
set -uo pipefail
IMG="${SUNNY_ROOT:-/root/sunny}/out/rootfs.img"
[ -f "$IMG" ] || { echo "ไม่พบ $IMG"; exit 1; }
for f in "$@"; do
  echo "==================== $f ===================="
  debugfs -R "cat $f" "$IMG" 2>/dev/null || echo "(อ่านไม่ได้/ไม่มีไฟล์)"
  echo
done
