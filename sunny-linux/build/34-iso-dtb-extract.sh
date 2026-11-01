#!/usr/bin/env bash
# 34-iso-dtb-extract.sh — แกะ linux-image/linux-modules deb: dtb ของ sm6150 + ตรวจ glue drivers
set -euo pipefail
ROOT="${SUNNY_ROOT:-/root/sunny}"
DX="$ROOT/iso/debs"
mkdir -p "$DX"

for D in /mnt/ubuiso/pool/main/l/linux-signed/linux-image-7.0.0-30-generic_*.deb \
         /mnt/ubuiso/pool/main/l/linux/linux-modules-7.0.0-30-generic_*.deb; do
  [ -f "$D" ] || continue
  B=$(basename "$D" .deb)
  mkdir -p "$DX/$B"
  dpkg-deb -x "$D" "$DX/$B"
done

echo "=== หา dtb ใน deb ที่แกะ ==="
find "$DX" -name '*.dtb' 2>/dev/null | head -20
echo "=== หา dtb โฟลเดอร์ qcom ==="
find "$DX" -type d -name 'qcom*' 2>/dev/null | head -10

echo "=== pinctrl/clk sm6150 ใน builtin ==="
MODS="$DX/$(ls "$DX" | grep linux-modules | head -1)/usr/lib/modules"
KVER=$(ls "$MODS" | head -1)
grep -Ei '6150|sm6[0-9]' "$MODS/$KVER/modules.builtin" 2>/dev/null | head -20 || echo "(ไม่พบใน builtin)"
echo "=== pinctrl/clk ทั้ง qcom ในตัว modules (.ko) ==="
find "$MODS/$KVER" -path '*pinctrl*' -name '*.ko*' 2>/dev/null | head -20
find "$MODS/$KVER" -path '*clk/qcom*' -name '*.ko*' 2>/dev/null | head -30
