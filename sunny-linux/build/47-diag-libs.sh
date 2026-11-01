#!/usr/bin/env bash
# 47-diag-libs.sh — ตรวจ lib ที่ขาดแบบละเอียด (mount image, ldd ผ่าน qemu)
set -u
SUNNY="${SUNNY_ROOT:-/root/sunny}"
M="$SUNNY/mnt-root"
pkill -f 'qemu' 2>/dev/null
sleep 1
mkdir -p "$M"
mountpoint -q "$M" || mount -o loop,rw "$SUNNY/out/rootfs.img" "$M" || exit 1
echo "--- mount ok: $(mountpoint "$M")"
echo "--- ldd: $(ls -l "$M/usr/bin/ldd" 2>&1)"
echo "--- libwrap.so.0: $(ls -l "$M/usr/lib/aarch64-linux-gnu/libwrap.so.0" 2>&1)"
echo "--- libpam: $(ls "$M/usr/lib/aarch64-linux-gnu/" 2>/dev/null | grep -c pam)"
cp -f /usr/bin/qemu-aarch64-static "$M/qemu" 2>&1 || echo "cp qemu failed"
mkdir -p "$M/dev" "$M/proc"
mountpoint -q "$M/dev"  || mount --bind /dev "$M/dev" 2>/dev/null
mountpoint -q "$M/proc" || mount -t proc proc "$M/proc" 2>/dev/null
echo "=== ldd sshd-session ==="
chroot "$M" /qemu /usr/bin/ldd /usr/lib/openssh/sshd-session 2>&1 | head -20
echo "=== ldd sshd ==="
chroot "$M" /qemu /usr/bin/ldd /usr/sbin/sshd 2>&1 | head -20
echo "=== ldd bash ==="
chroot "$M" /qemu /usr/bin/ldd /usr/bin/bash 2>&1 | head -20
