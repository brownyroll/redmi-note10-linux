#!/usr/bin/env bash
# 99-stat-rootfs.sh — stat ไฟล์ใน rootfs.img + ดูว่าเป็น symlink ไปไหน
set -uo pipefail
IMG="${SUNNY_ROOT:-/root/sunny}/out/rootfs.img"
for f in "$@"; do
  echo "==================== $f"
  debugfs -R "stat $f" "$IMG" 2>&1 | grep -E 'Inode:|Type:|Mode:|Size:|Link dest|Fast link dest|User:|Group:' 
done
