#!/usr/bin/env bash
set -u
K=/root/sunny/src/kernel
cd "$K" || exit 1
echo "=== FBDEV_EMULATION symbol ==="
grep -rn "config DRM_FBDEV_EMULATION" drivers/gpu/drm/ 2>/dev/null | head
echo
echo "=== drivers/video/msm ? ==="
ls drivers/video/ 2>/dev/null | head -20
echo
echo "=== FB_MSM kconfig ==="
grep -rn "config FB_MSM" drivers/video/msm/Kconfig drivers/video/msm/mdss/Kconfig 2>/dev/null | head
echo
echo "=== techpack ==="
ls techpack 2>/dev/null | head
echo
echo "=== drm msm kconfig files ==="
ls drivers/gpu/drm/msm/Kconfig drivers/gpu/drm/msm/dsi/Kconfig 2>/dev/null
echo
echo "=== DSI staging kconfig ==="
grep -rn "config DRM_MSM_DSI_STAGING" -A6 drivers/gpu/drm/msm/Kconfig 2>/dev/null | head -20
echo
echo "=== fbdev emulation usage in msm ==="
grep -rln "drm_fbdev" drivers/gpu/drm/msm/ 2>/dev/null | head
echo
echo "=== simplefb binding in DT? (panel/dsi nodes) ==="
grep -rn "dsi_display0\|sde_drm\|simple-framebuffer" arch/arm64/boot/dts/qcom/ 2>/dev/null | head -10
