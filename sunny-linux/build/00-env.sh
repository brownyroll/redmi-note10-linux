#!/usr/bin/env bash
# 00-env.sh — เตรียมเครื่อง build (รันใน WSL/Ubuntu 22.04+)
#   bash 00-env.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" = 0 ] && SUDO="" || SUDO="sudo"
export DEBIAN_FRONTEND=noninteractive

echo "==> host: $(uname -srm)  disk: $(df -h "$HERE" | awk 'NR==2{print $4" free"}')"

$SUDO apt-get update
$SUDO apt-get install -y --no-install-recommends \
  build-essential bc bison flex libssl-dev libelf-dev cpio rsync kmod \
  gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
  device-tree-compiler python3 python3-pip git curl zip unzip xz-utils \
  e2fsprogs android-sdk-libsparse-utils qemu-user-static \
  busybox-static

# mkbootimg: Ubuntu มี package ตรง หรือ fallback ไปใช้ AOSP source
if command -v mkbootimg >/dev/null 2>&1; then
  echo "  mkbootimg: $(command -v mkbootimg)"
elif [ -f "$HERE/../tools/mkbootimg/mkbootimg.py" ]; then
  echo "  mkbootimg: ใช้ AOSP ที่มีอยู่ ($HERE/../tools/mkbootimg/mkbootimg.py)"
else
  echo "  mkbootimg ไม่มี → โคลนจาก AOSP"
  git clone --depth 1 https://android.googlesource.com/platform/system/tools/mkbootimg "$HERE/../tools/mkbootimg"
fi

# ตรวจของที่ขาด
echo
for t in aarch64-linux-gnu-gcc dtc mke2fs cpio; do
  printf '  %-28s %s\n' "$t" "$(command -v "$t" || echo '❌ MISSING')"
done

echo
echo "==> OK  (RAM แนะนำ ≥ 8 GB, ดิสก์ ≥ 40 GB สำหรับ kernel+rootfs)"
free -h | awk 'NR<=2'
