#!/usr/bin/env bash
# 46-fix-libs.sh — หา shared lib ที่ขาดใน rootfs (จาก ldd) แล้วดึง .deb จาก pool ของ ISO มาใส่
set -u
SUNNY="${SUNNY_ROOT:-/root/sunny}"
OUT="$SUNNY/out"
M="$SUNNY/mnt-root"
ISO="$SUNNY/iso"
mkdir -p "$M"
mountpoint -q "$M" || mount -o loop,rw "$OUT/rootfs.img" "$M" || exit 1
cp /usr/bin/qemu-aarch64-static "$M/qemu"
mkdir -p "$M/dev" "$M/proc"
mountpoint -q "$M/dev"  || mount --bind /dev "$M/dev" 2>/dev/null
mountpoint -q "$M/proc" || mount -t proc proc "$M/proc" 2>/dev/null

BINS="/usr/sbin/sshd /usr/lib/openssh/sshd-session /usr/lib/openssh/sshd-auth /usr/bin/ssh-keygen /usr/bin/ip /sbin/agetty /usr/bin/setsid /usr/bin/mountpoint /usr/bin/bash /usr/bin/dash"
MISSING=""
for b in $BINS; do
  [ -e "$M$b" ] || continue
  out=$(chroot "$M" /qemu /usr/bin/ldd "$b" 2>&1)
  notfound=$(echo "$out" | grep -o '[^ ]*not found' | awk '{print $1}' | sort -u)
  if [ -n "$notfound" ]; then
    echo "== $b ขาด: $notfound"
    MISSING="$MISSING $notfound"
  fi
done
MISSING=$(echo "$MISSING" | tr ' ' '\n' | sort -u | sed '/^$/d')

if [ -z "$MISSING" ]; then
  echo "✓ ไม่มี lib ขาด"
  rm -f "$M/qemu"
  exit 0
fi
echo "== lib ที่ต้องหา: $MISSING"

# ค้นใน Packages index ของ pool (ถ้ามี) หรือใช้ apt-get download ของ arm64
POOL_PKGS="$ISO/pkgs_index.txt"
if [ ! -f "$POOL_PKGS" ]; then
  ( cd "$ISO" && find . -name 'Packages*' 2>/dev/null | head -5 )
fi

# วิธีที่ชัวร์: ใช้ apt ของ Ubuntu arm64 ผ่าน sources.list ที่ชี้ ports (ดาวน์โหลดเฉพาะ .deb)
WORK="$SUNNY/tmp/debs"
mkdir -p "$WORK"
for lib in $MISSING; do
  name=$(echo "$lib" | sed 's/^lib/lib/; s/\.so.*$//')
  name="${name%%.*}"
  # libwrap.so.0 -> libwrap0 ; libc.so.6 -> libc6 ; libpam.so.0 -> libpam0g
  case "$lib" in
    libwrap.so.0)  pkg="libwrap0" ;;
    libc.so.6)     pkg="libc6" ;;
    libpam.so.0)   pkg="libpam0g" ;;
    libcrypto.so.*|libssl.so.*) pkg="libssl3t64" ;;
    libcrypt.so.1) pkg="libcrypt1" ;;
    *)             pkg="$name" ;;
  esac
  echo "--> $lib => $pkg"
  ( cd "$WORK" && apt-get download "$pkg" -o APT::Architecture=arm64 2>&1 | tail -2 )
done

for d in "$WORK"/*.deb; do
  [ -f "$d" ] || continue
  echo "== แตก $d"
  dpkg -x "$d" "$M"
done
rm -f "$M/qemu"
echo "เสร็จ — ตรวจซ้ำด้วย 46-fix-libs.sh อีกรอบ"
