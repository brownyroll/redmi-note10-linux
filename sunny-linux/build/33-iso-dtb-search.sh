#!/usr/bin/env bash
# 33-iso-dtb-search.sh — ตรวจ: (1) SoC glue drivers in builtins, (2) mainline dtb ใน pool
set -euo pipefail
ROOT="${SUNNY_ROOT:-/root/sunny}"
SQQ="$ROOT/iso/sq"
MODS="$SQQ/usr/lib/modules"
KVER=$(ls "$MODS" | head -1)
M="$MODS/$KVER"
CFG="$SQQ/boot/config-$KVER"

echo "=== builtin: ตระกูล qcom SoC glue ==="
grep -Ei 'pinctrl_sm6150|gcc_sm6150|sm6150|serial_qcom_geni|geni|qcom_rpmh|icc_rpm|qcom_cc|interconnect_qcom' \
  "$M/modules.builtin" 2>/dev/null | head -40 || true

echo "=== config geni + rpmh + icc ==="
for OPT in CONFIG_SERIAL_QCOM_GENI CONFIG_SERIAL_QCOM_GENI_CONSOLE CONFIG_QCOM_RPMH \
           CONFIG_QCOM_ICC_RPM CONFIG_QCOM_INTERCONNECT CONFIG_QCOM_CLK_RPMH \
           CONFIG_QCOM_SMD_RPM CONFIG_QCOM_GLINK_SSR CONFIG_QCOM_GSBI CONFIG_QCOM_QSECOM; do
  grep -E "^$OPT" "$CFG" 2>/dev/null || true
done

echo "=== pool/main/l/linux* ==="
ls -d /mnt/ubuiso/pool/main/l/linux* 2>/dev/null | head -10
ls /mnt/ubuiso/pool/main/l/ 2>/dev/null | head -50

echo "=== หา linux-image deb ใน ISO (รวม sub) ==="
find /mnt/ubuiso/pool -name 'linux-image-*.deb' 2>/dev/null | head -10
find /mnt/ubuiso/pool -name 'linux-modules-*.deb' 2>/dev/null | head -10
