#!/usr/bin/env bash
# 01-sources.sh — โคลน kernel + device tree ของ sunny
#   bash 01-sources.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${SUNNY_ROOT:-$HERE/..}/src"
mkdir -p "$SRC"

clone() { # repo branch dir
  if [ -d "$3/.git" ]; then echo "  มีแล้ว: $3"; return; fi
  echo "==> clone $1 ($2)"
  git clone --depth 1 -b "$2" "$1" "$3"
}

# kernel 4.14.206 CAF LA.UM.9.1 — มี dts + defconfig ของ sunny/mojito
clone https://github.com/Neternels/android_kernel_xiaomi_sunny LA.UM.9.1 "$SRC/kernel"

# device tree YAAP — ใช้ดู base address / cmdline / pagesize ของ boot header
clone https://github.com/yaap/device_xiaomi_sunny sixteen "$SRC/device_xiaomi_sunny"

# เก็บค่าที่ต้องใช้แพ็ก boot ไว้เทียบ
echo
echo "==> ค่าจาก device tree (ใช้กับ 05-bootimg.sh):"
grep -hE 'BOARD_KERNEL_(BASE|PAGESIZE|OFFSET|TAGS_OFFSET|CMDLINE)' \
  "$SRC/device_xiaomi_sunny/BoardConfig.mk" 2>/dev/null || echo "  (ไม่พบ BoardConfig.mk)"

echo
echo "==> defconfig ที่มี:"
ls "$SRC/kernel/arch/arm64/configs" | grep -iE 'sunny|mojito|vendor' | head -20

echo
echo "==> DTS ของ sunny:"
find "$SRC/kernel/arch/arm64/boot/dts" -iname '*sunny*' -o -iname '*mojito*' 2>/dev/null | head -20

du -sh "$SRC"/*
