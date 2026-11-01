#!/usr/bin/env bash
# 31-iso-inspect.sh — ตรวจ ISO Ubuntu Server arm64: kernel + squashfs + modules
set -euo pipefail
ROOT="${SUNNY_ROOT:-/root/sunny}"
ISO="$ROOT/iso/ubuntu-26.04.1-live-server-arm64.iso"
MNT=/mnt/ubuiso
mkdir -p "$MNT"
mountpoint -q "$MNT" || mount -o loop,ro "$ISO" "$MNT"

echo "=== ขนาดไฟล์สำคัญ ==="
ls -lh "$MNT"/casper/vmlinuz "$MNT"/casper/initrd "$MNT"/casper/*.squashfs

echo "=== mount squashfs ตัว server-minimal ==="
SQ="$MNT/casper/ubuntu-server-minimal.squashfs"
SQQ="$ROOT/iso/sq"
mkdir -p "$SQQ"
mountpoint -q "$SQQ" || mount -o loop,ro "$SQ" "$SQQ"

echo "=== kernel ใน squashfs ==="
KVER=$(ls "$SQQ/lib/modules" 2>/dev/null | head -1)
echo "KVER=$KVER"
ls -lh "$SQQ/boot" 2>/dev/null | head
echo "=== config สำคัญ ==="
KCFG="$SQQ/boot/config-$KVER"
[ -f "$KCFG" ] || KCFG="$SQQ/usr/lib/modules/$KVER/config"
for OPT in CONFIG_USB_CONFIGFS CONFIG_USB_F_RNDIS CONFIG_EXT4FS CONFIG_MODVERSIONS CONFIG_WATCHDOG_QCOM CONFIG_QCOM_WDT; do
  grep -E "^$OPT" "$KCFG" 2>/dev/null || true
done
echo "=== พิมพ์ vmlinuz ==="
file "$MNT"/casper/vmlinuz

echo "=== หาไดรเวอร์ SM6150 / trinket / sdm678 ใน modules ==="
MODS="$SQQ/usr/lib/modules/$KVER"
[ -d "$MODS" ] || MODS="$SQQ/lib/modules/$KVER"
grep -ril sm6150 "$MODS" 2>/dev/null | head -5 || echo "(ไม่พบ sm6150)"
grep -ril trinket "$MODS" 2>/dev/null | head -5 || echo "(ไม่พบ trinket)"
grep -ril sdm678 "$MODS" 2>/dev/null | head -5 || echo "(ไม่พบ sdm678)"
echo "=== dts ใน dtb ที่แถม? ==="
ls "$SQQ/boot" 2>/dev/null | grep -ci dtb || true
