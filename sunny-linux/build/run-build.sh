#!/usr/bin/env bash
# run-build.sh — ตัวขับ build ทั้งหมดใน WSL (รันด้วย root: wsl -u root bash run-build.sh all)
#   stage: env | sources | kernel | rootfs | initramfs | bootimg | all
set -uo pipefail
SUNNY_ROOT="${SUNNY_ROOT:-/root/sunny}"
SRC_C="/mnt/c/Users/brown/Documents/Default Project/sunny-linux"
STAGE="${1:-all}"

mkdir -p "$SUNNY_ROOT/logs" "$SUNNY_ROOT/build" "$SUNNY_ROOT/src"
cp -f "$SRC_C"/build/*.sh "$SRC_C"/build/sunny.fragment "$SUNNY_ROOT/build/" 2>/dev/null
export SUNNY_ROOT
cd "$SUNNY_ROOT/build"

run() { # name script
  echo "=== [$1] $(date -u +%H:%M:%S) ==="
  bash "$2" 2>&1 | tee -a "$SUNNY_ROOT/logs/$1.log"
  local rc=${PIPESTATUS[0]}
  echo "=== [$1] exit=$rc ==="
  return $rc
}

case "$STAGE" in
  env)       run env 00-env.sh ;;
  sources)   run sources 01-sources.sh ;;
  kernel)    run patches patches.sh; run kernel 02-kernel.sh ;;
  rootfs)    run rootfs 03-rootfs.sh ;;
  initramfs) run initramfs 04-initramfs.sh ;;
  bootimg)   run bootimg 05-bootimg.sh ;;
  all)
    run env 00-env.sh || exit 1
    run sources 01-sources.sh || exit 1
    run kernel 02-kernel.sh || exit 1
    run initramfs 04-initramfs.sh || true
    run bootimg 05-bootimg.sh || true
    ;;
  *) echo "stage ไม่รู้จัก: $STAGE"; exit 2 ;;
esac
