#!/usr/bin/env bash
# 03-rootfs.sh — สร้าง Ubuntu 24.04 arm64 rootfs → rootfs.img (ext4, label sunny-root)
#   ต้องมี root (chroot) และ qemu-user-static (รัน ARM ใน x86)
#   bash 03-rootfs.sh [SIZE=6G]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
OUT="$ROOT/out"
SIZE="${1:-6G}"
R="$OUT/rootfs"
IMG="$OUT/rootfs.img"
[ "$(id -u)" = 0 ] && SUDO="" || SUDO="sudo"
BASEURL="https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release"
mkdir -p "$OUT"

# ---- 1. โหลด ubuntu-base ----
TARBALL=$(curl -s "$BASEURL/" | grep -oE 'ubuntu-base-24\.04[0-9.]*-base-arm64\.tar\.gz' | sort -u | tail -1)
[ -n "$TARBALL" ] || { echo "หา ubuntu-base ไม่เจอที่ $BASEURL"; exit 1; }
[ -f "$OUT/$TARBALL" ] || curl -L --no-progress-meter -o "$OUT/$TARBALL" "$BASEURL/$TARBALL"
echo "==> base: $TARBALL ($(du -h "$OUT/$TARBALL" | cut -f1))"

# ---- 2. แตกไฟล์ ----
# เก็บกวาด mount ค้างจากรอบก่อน (ถ้ามี) ไม่งั้น rm จะล้ม
for m in proc sys dev; do $SUDO umount -l "$R/$m" 2>/dev/null || true; done
$SUDO rm -rf "$R"; mkdir -p "$R"
$SUDO tar -xpf "$OUT/$TARBALL" -C "$R"
$SUDO cp /usr/bin/qemu-aarch64-static "$R/usr/bin/"

# ---- 3. chu_root: ตั้งค่าข้างใน ----
$SUDO tee "$R/tmp/chroot-setup.sh" >/dev/null <<'EOS'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
# proc/sys/dev ถูก bind mount จาก host แล้ว (ดูด้านล่าง) — ห้าม mount ซ้ำ
cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# ห้าม postinst เปิด service ใน chroot
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

apt-get update
apt-get install -y --no-install-recommends \
  systemd-sysv systemd openssh-server sudo iproute2 iputils-ping \
  net-tools usbutils less nano ca-certificates tzdata kmod udev

# user
groupadd -f sudo
id -u dev >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo dev
echo 'dev:ubuntu1234' | chpasswd
echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-dev
chmod 440 /etc/sudoers.d/90-dev

# hostname / fstab
echo sunny > /etc/hostname
printf '127.0.0.1 localhost\n127.0.1.1 sunny\n' > /etc/hosts
cat > /etc/fstab <<'FSTAB'
LABEL=sunny-root  /      ext4  defaults,noatime  0 1
tmpfs             /tmp   tmpfs defaults,nosuid  0 0
FSTAB

# console ทาง USB (ttyGS0) + ttyMSM0
systemctl enable serial-getty@ttyGS0.service 2>/dev/null || true

# ssh: อนุญาต password + root no
mkdir -p /etc/ssh/sshd_config.d
printf 'PasswordAuthentication yes\nPermitRootLogin no\n' > /etc/ssh/sshd_config.d/99-sunny.conf
ssh-keygen -A
systemctl enable ssh

# service ที่ไม่มีประโยชน์/ทำให้ boot ค้างบนเครื่องนี้
systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
systemctl mask systemd-resolved.service 2>/dev/null || true
systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

# network แบบ static บน USB gadget (usb0) + dhcp client สำหรับ wifi
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/10-usb0.network <<'NET'
[Match]
Name=usb0
[Network]
Address=192.168.42.2/24
NET
systemctl enable systemd-networkd

# ---- USB gadget (configfs): RNDIS → usb0 + ACM → ttyGS0 ----
# ไม่มี legacy g_ether/g_serial ใน kernel นี้ และ kernel ไม่มี Android init
# ถ้าไม่ตั้ง configfs เอง จะไม่มีทั้ง usb0 และ ttyGS0 = เข้าเครื่องไม่ได้เลย
cat > /usr/local/sbin/usb-gadget.sh <<'GADGET'
#!/bin/bash
# ตั้ง USB gadget ผ่าน configfs — RNDIS (usb0) + ACM (ttyGS0, ถ้า kernel รองรับ)
set -u
G=/sys/kernel/config/usb_gadget/g1

mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config || exit 1

# รอให้ dwc3 ลงทะเบียน UDC (สูงสุด 30 วิ)
i=0
while [ -z "$(ls /sys/class/udc 2>/dev/null)" ]; do
  i=$((i+1)); [ "$i" -gt 30 ] && { echo "ไม่พบ UDC (dwc3 ยังไม่พร้อม)"; exit 1; }
  sleep 1
done
UDC=$(ls /sys/class/udc | head -1)

if [ ! -d "$G" ]; then
  mkdir -p "$G"
  echo 0x1d6b > "$G/idVendor"
  echo 0x0104 > "$G/idProduct"
  echo 0x0100 > "$G/bcdDevice"
  echo 0x0200 > "$G/bcdUSB"
  echo 0xEF > "$G/bDeviceClass"
  echo 0x02 > "$G/bDeviceSubClass"
  echo 0x01 > "$G/bDeviceProtocol"

  mkdir -p "$G/strings/0x409"
  echo "579a9d18"        > "$G/strings/0x409/serialnumber"
  echo "sunny-linux"     > "$G/strings/0x409/manufacturer"
  echo "Ubuntu (sunny)"  > "$G/strings/0x409/product"

  mkdir -p "$G/configs/c.1/strings/0x409"
  echo "rndis"  > "$G/configs/c.1/strings/0x409/configuration"
  echo 250      > "$G/configs/c.1/MaxPower"

  # RNDIS → usb0
  mkdir -p "$G/functions/rndis.usb0"
  mkdir -p "$G/functions/rndis.usb0/os_desc/interface.rndis" 2>/dev/null || true
  echo "RNDIS"    > "$G/functions/rndis.usb0/os_desc/interface.rndis/compatible_id"      2>/dev/null || true
  echo "5162001"  > "$G/functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id"  2>/dev/null || true
  ln -sf "$G/functions/rndis.usb0" "$G/configs/c.1/"

  # ACM → ttyGS0 (สำหรับ serial console สำรอง)
  if mkdir -p "$G/functions/acm.GS0" 2>/dev/null; then
    ln -sf "$G/functions/acm.GS0" "$G/configs/c.1/"
    echo "ACM เปิดแล้ว (ttyGS0)"
  fi

  # Microsoft OS descriptors ให้ Windows จับ RNDIS อัตโนมัติ
  echo 1        > "$G/os_desc/use"          2>/dev/null || true
  echo 0xcd     > "$G/os_desc/b_vendor_code" 2>/dev/null || true
  echo "MSFT100" > "$G/os_desc/qw_sign"      2>/dev/null || true
fi

echo "$UDC" > "$G/UDC" || exit 1
echo "gadget ผูกกับ $UDC แล้ว"
sleep 2
ip link set usb0 up 2>/dev/null || true
exit 0
GADGET
chmod +x /usr/local/sbin/usb-gadget.sh

cat > /etc/systemd/system/usb-gadget.service <<'UNIT'
[Unit]
Description=USB gadget (RNDIS usb0 + ACM ttyGS0)
After=sysinit.target local-fs.target systemd-modules-load.service
Wants=sysinit.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/usb-gadget.sh
TimeoutStartSec=60
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable usb-gadget.service

# ---- ขยาย rootfs ให้เต็มพาร์ทิชัน (fs เริ่ม 6 GB แต่ userdata มี ~112 GB) ----
cat > /usr/local/sbin/resize-rootfs.sh <<'RESIZE'
#!/bin/bash
# ขยาย ext4 ของ root partition ให้เต็มพาร์ทิชัน (online resize)
set -u
DEV=$(findmnt -n -o SOURCE /)
[ -n "$DEV" ] || { echo "ไม่พบ root device"; exit 1; }
# fs เต็มแล้ว → resize2fs error เงียบ ๆ; กูรูไม่ต้องรันซ้ำ
resize2fs "$DEV"
exit 0
RESIZE
chmod +x /usr/local/sbin/resize-rootfs.sh

cat > /etc/systemd/system/resize-rootfs.service <<'UNIT2'
[Unit]
Description=Resize root filesystem to fill userdata
After=local-fs.target usb-gadget.service
Before=ssh.service
ConditionPathIsMountPoint=/

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/resize-rootfs.sh

[Install]
WantedBy=multi-user.target
UNIT2
systemctl enable resize-rootfs.service

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/chroot-setup.sh
EOS
$SUDO chmod +x "$R/tmp/chroot-setup.sh"

# ---- 4. เข้า chroot (qemu) ----
cleanup() {
  for m in dev sys proc; do $SUDO umount -l "$R/$m" 2>/dev/null || true; done
  $SUDO rm -f "$R/usr/bin/qemu-aarch64-static"
}
trap cleanup EXIT
for m in proc sys dev; do $SUDO mount --bind /$m "$R/$m"; done
$SUDO chroot "$R" /usr/bin/qemu-aarch64-static /bin/bash /tmp/chroot-setup.sh
cleanup; trap - EXIT

# ---- 5. ทำ ext4 image (ไม่ต้องใช้ loop device — WSL ใช้ได้) ----
echo "==> สร้าง $IMG ($SIZE)"
rm -f "$IMG"
mke2fs -q -t ext4 -L sunny-root -d "$R" -F "$IMG" "$SIZE"
e2fsck -fy "$IMG" >/dev/null 2>&1 || true

echo
echo "เสร็จ: $IMG"
echo "  label : sunny-root"
echo "  ขนาด  : $(du -h "$IMG" | cut -f1) (sparse)"
echo "  user  : dev / ubuntu1234   ssh:22"
