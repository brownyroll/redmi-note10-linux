#!/usr/bin/env bash
# 35-iso-dtb-qcom.sh — รายการ dtb qcom ใน linux-modules deb + glue drivers
set -uo pipefail
D=/root/sunny/iso/debs/linux-modules-7.0.0-30-generic_7.0.0-30.30_arm64/usr/lib/firmware/7.0.0-30-generic/device-tree

echo "=== dtb qcom ที่มี (โฟลเดอร์ qcom) ==="
ls "$D/qcom" 2>/dev/null | bash -c 'cat' | head -60
echo "=== หา 6150 / sm61 / 678 / trinket ทั้ง device-tree ==="
find "$D" -maxdepth 3 -iname '*6150*' -o -maxdepth 3 -iname '*trinket*' -o -maxdepth 3 -iname '*678*' 2>/dev/null

MODS=/root/sunny/iso/debs/linux-modules-7.0.0-30-generic_7.0.0-30.30_arm64/usr/lib/modules/7.0.0-30-generic
echo "=== มีโฟลเดอร์นี้จริงไหม ==="
ls "$MODS" 2>/dev/null | head -5 || echo "ไม่มี modules ใน deb นี้หรือ path ผิด"

echo "=== builtin: pinctrl/clk qcom sm6xx ==="
grep -Ei 'sm6|sdm6|pinctrl_sm|gcc' "$MODS/modules.builtin" 2>/dev/null | head -30

echo "=== .ko zst รายการ pinctrl qcom ==="
find "$MODS/kernel/drivers/pinctrl/qcom" -type f 2>/dev/null | head -30

echo "=== .ko zst รายการ clk qcom (близый) ==="
find "$MODS/kernel/drivers/clk/qcom" -type f 2>/dev/null | grep -Ei 'sm6|sdm6|gcc-|clk-rpmh' | head -30
