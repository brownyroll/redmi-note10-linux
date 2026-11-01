#!/usr/bin/env bash
# A8-prepare-pmos-kernel.sh — ใส่ Image/dtb ที่พิสูจน์แล้วลงใน kernel package ของ pmOS
set -eu
A=/root/sunny/src/pmaports/device/testing
K=$A/linux-xiaomi-sunny-prebuilt
O=/root/sunny/out
mkdir -p "$K"

# kernel ที่บูตได้จริง = ดึงจาก boot-yaap-k.img (NetErnels-YAAP 4.14.206)
[ -f /tmp/uyaap/kernel ] || python3 /root/sunny/tools/mkbootimg/unpack_bootimg.py --boot_img "$O/boot-yaap-k.img" --out /tmp/uyaap >/dev/null
cp -f /tmp/uyaap/kernel "$K/Image"
[ -f /tmp/unpacked-vb/dtb ] || [ -f "$O/unpacked-vb/dtb" ] && cp -f "${O}/unpacked-vb/dtb" "$K/dtb" 2>/dev/null || true
if [ ! -f "$K/dtb" ]; then
  rm -rf /tmp/uvb
  python3 /root/sunny/tools/mkbootimg/unpack_bootimg.py --boot_img "$O/vendor_boot.img" --out /tmp/uvb >/dev/null
  cp -f /tmp/uvb/dtb "$K/dtb"
fi

cat > "$K/APKBUILD" <<'EOF'
# Prebuilt kernel for Xiaomi Redmi Note 10 (sunny)
# This is the NetErnels/YAAP 4.14.206 Image that is proven to boot on this
# device (display via DRM/KMS works, USB gadget works). We do not rebuild it
# inside pmbootstrap: the source tree we have produces an Image that the
# bootloader does not start.
pkgname=linux-xiaomi-sunny-prebuilt
pkgver=4.14.206
pkgrel=0
pkgdesc="Prebuilt 4.14.206 kernel for Xiaomi Redmi Note 10 (sunny)"
arch="aarch64"
_flavor="xiaomi-sunny"
url="https://kernel.org"
license="GPL-2.0-only"
options="!strip !check !tracedeps !archcheck"
source="Image dtb"

package() {
	install -Dm644 "$srcdir/Image" "$pkgdir/boot/vmlinuz-$_flavor"
	install -Dm644 "$srcdir/dtb"   "$pkgdir/boot/dtbs/qcom/sdm678-xiaomi-sunny.dtb"
	mkdir -p "$pkgdir/lib/modules/$pkgver-$_flavor"
}
EOF

ls -l "$K"
echo
echo "=== sha ==="
sha256sum "$K/Image" "$K/dtb"
