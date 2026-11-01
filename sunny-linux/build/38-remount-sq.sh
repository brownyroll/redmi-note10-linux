#!/usr/bin/env bash
# 38-remount-sq.sh — remount squashfs ของ ISO ที่ /root/sunny/iso/sq แล้วรัน 37-rootfs-iso.sh
set -euo pipefail
ROOT="${SUNNY_ROOT:-/root/sunny}"
SQ="$ROOT/iso/casper-mnt/ubuntu-server-minimal.squashfs"
ISO="$ROOT/iso/ubuntu-26.04.1-live-server-arm64.iso"
MNT=/mnt/ubuiso
SQQ="$ROOT/iso/sq"

mountpoint -q "$MNT" || mount -o loop,ro "$ISO" "$MNT"
SQ="$MNT/casper/ubuntu-server-minimal.squashfs"
mkdir -p "$SQQ"
mountpoint -q "$SQQ" || mount -o loop,ro "$SQ" "$SQQ"
[ -f "$SQQ/lib/systemd/systemd" ] || { echo "mount squashfs ไม่สมบูรณ์"; exit 1; }
echo "squashfs พร้อม: $(du -sh "$SQQ" | cut -f1)"
HERE="$(cd "$(dirname "$0")" && pwd)"
bash "$HERE/37-rootfs-iso.sh" "${1:-}"
