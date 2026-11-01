#!/usr/bin/env bash
# 32-iso-kernel-check.sh — ตรวจชัดว่า kernel 7.0 generic รองรับ SM6150/trinket พอบูตได้ไหม
set -euo pipefail
ROOT="${SUNNY_ROOT:-/root/sunny}"
SQQ="$ROOT/iso/sq"
MODS="$SQQ/usr/lib/modules"
KVER=$(ls "$MODS" | head -1)
M="$MODS/$KVER"
CFG="$SQQ/boot/config-$KVER"

echo "=== alias ที่อ้าง sm6150 ==="
grep -i sm6150 "$M/modules.alias" | sort -u | head -30

echo "=== builtin ที่อ้าง sm6150 ==="
grep -i sm6150 "$M/modules.builtin" 2>/dev/null | head -10 || true

echo "=== config ที่เกี่ยว ==="
for OPT in CONFIG_EXT4_FS CONFIG_ARCH_QCOM CONFIG_COMMON_CLK_QCOM CONFIG_PINCTRL_SM6150 \
           CONFIG_PHY_QCOM_QUSB2 CONFIG_MSM_GCC_6150 CONFIG_SM_GCC_6150 CONFIG_DWC3_QCOM \
           CONFIG_USB_DWC3_QCOM CONFIG_PINCTRL_MSM CONFIG_SERIAL_MSM CONFIG_QCOM_SOCINFO \
           CONFIG_QCOM_SMEM CONFIG_REGULATOR_QCOM_SPMI CONFIG_QCOM_SPMI_IADC CONFIG_QCOM_WATCHDOG; do
  grep -E "^$OPT" "$CFG" 2>/dev/null || true
done

echo "=== modules จริงที่มีเกี่ยว sm6150/qcom ตระกูลบูต ==="
find "$M" -name '*sm6150*' -o -name '*gcc-sm6150*' 2>/dev/null | head -10
echo "=== dwc3 ==="
find "$M" -name 'dwc3*' | head
echo "=== serial msm ==="
find "$M" -name '*msm*' | grep -Ei 'serial|uart' | head
