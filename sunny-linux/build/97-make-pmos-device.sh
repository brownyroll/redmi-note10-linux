#!/usr/bin/env bash
# 97-make-pmos-device.sh — สร้าง device package สำหรับ postmarketOS (sunny, downstream 4.14)
set -eu
A=/root/sunny/src/pmaports/device/testing
D=$A/device-xiaomi-sunny-downstream
K=$A/linux-xiaomi-sunny-prebuilt
mkdir -p "$D" "$K"

cat > "$D/deviceinfo" <<'EOF'
# Reference: <https://postmarketos.org/deviceinfo>
# Xiaomi Redmi Note 10 (sunny, SM6150/SDM678) — downstream 4.14 port
# หมายเหตุ: เครื่องนี้มีพาร์ทิชัน vendor_boot → header v4, dtb+initramfs อยู่ที่ vendor_boot
deviceinfo_format_version="0"
deviceinfo_name="Xiaomi Redmi Note 10 (downstream)"
deviceinfo_manufacturer="Xiaomi"
deviceinfo_codename="xiaomi-sunny-downstream"
deviceinfo_year="2021"
deviceinfo_arch="aarch64"

# Device
deviceinfo_chassis="handset"
deviceinfo_keyboard="false"
deviceinfo_external_storage="true"
deviceinfo_screen_width="1080"
deviceinfo_screen_height="2400"

# Bootloader / boot image
deviceinfo_flash_method="fastboot"
deviceinfo_generate_bootimg="true"
deviceinfo_header_version="4"
deviceinfo_bootimg_qcdt="false"
deviceinfo_flash_sparse="true"
deviceinfo_flash_pagesize="4096"
deviceinfo_flash_offset_base="0x00000000"
deviceinfo_flash_offset_kernel="0x00008000"
deviceinfo_flash_offset_ramdisk="0x01000000"
deviceinfo_flash_offset_second="0x00f00000"
deviceinfo_flash_offset_tags="0x00000100"
deviceinfo_flash_offset_dtb="0x01f00000"

# cmdline — console=tty0 ตัวแรก สำคัญสำหรับ fbcon (จอ)
deviceinfo_kernel_cmdline="console=tty0 console=ttyMSM0,115200n8 androidboot.hardware=qcom androidboot.usbcontroller=a600000.dwc3 loop.max_part=7 lpm_levels.sleep_disabled=1 service_locator.enable=1 swiotlb=1 msm_rtb.filter=0x237 kpti=off"

# USB (Xiaomi RNDIS) — ให้ pmOS ทำ USB net เองได้
deviceinfo_usb_idVendor="0x2717"
deviceinfo_usb_idProduct="0xff80"
deviceinfo_usb_network_function="rndis_bam.rndis"
EOF

cat > "$D/APKBUILD" <<'EOF'
# Reference: <https://postmarketos.org/devicepkg>
pkgname=device-xiaomi-sunny-downstream
pkgdesc="Xiaomi Redmi Note 10 (sunny) downstream port"
pkgver=0.1
pkgrel=0
url="https://postmarketos.org"
license="MIT"
arch="aarch64"
options="!check !archcheck"
depends="linux-xiaomi-sunny-prebuilt mkbootimg postmarketos-base"
makedepends="devicepkg-dev"
source="deviceinfo"

build() {
	devicepkg_build $startdir $pkgname
}

package() {
	devicepkg_package $startdir $pkgname
}
EOF

cat > "$K/APKBUILD" <<'EOF'
# linux-xiaomi-sunny-prebuilt — ไม่คอมไพล์ใน pmbootstrap
# ใช้ Image/dtb/modules ที่ build จาก tree 4.14.206 (ตัวที่บูตได้จริงบนเครื่องนี้)
# วิธีใช้: pmbootstrap build --src=/root/sunny/src/kernel linux-xiaomi-sunny-prebuilt
pkgname=linux-xiaomi-sunny-prebuilt
pkgver=4.14.206
pkgrel=0
pkgdesc="Prebuilt 4.14.206 kernel for Xiaomi Redmi Note 10 (sunny)"
arch="aarch64"
_flavor="xiaomi-sunny"
url="https://kernel.org"
license="GPL-2.0-only"
options="!strip !check !tracedeps !archcheck"
source=""

package() {
	install -Dm644 "$startdir/Image"   "$pkgdir/boot/vmlinuz-$_flavor"
	install -Dm644 "$startdir/dtb"     "$pkgdir/boot/dtbs/qcom/sdm678-xiaomi-sunny.dtb"
}
EOF

echo "created:"
find "$A" -maxdepth 2 -path '*sunny*' -type f | sort
echo
echo "=== deviceinfo ==="
cat "$D/deviceinfo" | grep -v '^#' | sed '/^$/d'
