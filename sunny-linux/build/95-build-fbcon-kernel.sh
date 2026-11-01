#!/usr/bin/env bash
# 95-build-fbcon-kernel.sh — สร้าง Image ใหม่จาก .config เดิม (ที่บูตได้) + เปิด fbdev ให้จอมี fb0
set -u
K=/root/sunny/src/kernel
O=/root/sunny/out
cd "$K" || exit 1
export ARCH=arm64 SUBARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
export KBUILD_BUILD_USER=sunny KBUILD_BUILD_HOST=sunny-linux
export KCFLAGS="-Wno-error -Wno-array-bounds -Wno-stringop-overflow -Wno-dangling-pointer -Wno-use-after-free -Wno-format-overflow"

cp -f "$O/Image" "$O/Image.prev" 2>/dev/null && echo "backup: $O/Image.prev"

echo "==> prepare scripts/config"
make O="$O" scripts >/dev/null 2>&1
CFG="$K/scripts/config"
[ -x "$O/scripts/config" ] && CFG="$O/scripts/config"
echo "using cfg: $CFG"

echo "==> enable fbdev + console"
$CFG --file "$O/.config" -e DRM_FBDEV_EMULATION
$CFG --file "$O/.config" -e FB
$CFG --file "$O/.config" -e FRAMEBUFFER_CONSOLE
$CFG --file "$O/.config" -e VT
$CFG --file "$O/.config" -e VT_CONSOLE
$CFG --file "$O/.config" -e DRM
$CFG --file "$O/.config" -e DRM_MSM
if grep -q "^config DRM_MSM_SDE" drivers/gpu/drm/msm/Kconfig; then
  echo "    + DRM_MSM_SDE"
  $CFG --file "$O/.config" -e DRM_MSM_SDE
fi
if grep -q "^config DRM_MSM_DSI_STAGING" drivers/gpu/drm/msm/Kconfig; then
  $CFG --file "$O/.config" -e DRM_MSM_DSI_STAGING
fi

make O="$O" olddefconfig >/dev/null 2>&1
echo "==> config check"
grep -E 'CONFIG_DRM_FBDEV_EMULATION|CONFIG_DRM_MSM_SDE|CONFIG_FRAMEBUFFER_CONSOLE|CONFIG_DRM_MSM=|CONFIG_FB=' "$O/.config"

echo "==> build Image -j$(nproc)"
make O="$O" -j"$(nproc)" Image 2>&1 | tee "$O/build-fbcon.log" | tail -25

if [ -f "$O/arch/arm64/boot/Image" ]; then
  cp -f "$O/arch/arm64/boot/Image" "$O/Image.fbcon"
  ls -l "$O/Image.fbcon"
  echo "FB CON KERNEL OK"
else
  echo "BUILD FAILED"
  tail -40 "$O/build-fbcon.log"
fi
