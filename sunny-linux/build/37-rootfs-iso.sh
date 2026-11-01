#!/usr/bin/env bash
# 37-rootfs-iso.sh — สร้าง rootfs.img จาก ISO Ubuntu 26.04 (squashfs) ให้พอดีเครื่อง sunny
#   ผลลัพธ์: out/rootfs.img (ext4 label=sunny-root) + out/rootfs.simg (sparse สำหรับ fastboot)
#   bash 37-rootfs-iso.sh [SIZE=8G]
set -euo pipefail
ROOT="${SUNNY_ROOT:-/root/sunny}"
SQQ="$ROOT/iso/sq"
OUT="$ROOT/out"
R="$OUT/rootfs-iso"
SIZE="${1:-8G}"

[ -f "$SQQ/lib/systemd/systemd" ] || { echo "ไม่มี squashfs — รัน 31-iso-inspect.sh ก่อน"; exit 1; }
command -v qemu-aarch64-static >/dev/null || { echo "ขาด qemu-aarch64-static"; exit 1; }
command -v mke2fs >/dev/null || { echo "ขาด e2fsprogs"; exit 1; }
command -v img2simg >/dev/null || { echo "ขาด img2simg (android-sdk-libsparse-utils)"; exit 1; }

# ---- 1. หา openssh-server ใน ISO pool แล้วแตก ----
mapfile -t SSH_DEBS < <(find /mnt/ubuiso -name 'openssh-server*.deb' -o -name 'openssh-client*.deb' \
  -o -name 'openssh-sftp-server*.deb' 2>/dev/null | sort -u)

[ ${#SSH_DEBS[@]} -gt 0 ] || { echo "ไม่พบ opensh-server/client ใน ISO!"; exit 1; }
echo "openssh deb พบ: ${#SSH_DEBS[@]} ตัว"

# ---- 2. copy squashfs → R (ไม่มี qemu อะไร แค่สร้าง) ----
rm -rf "$R"; mkdir -p "$R"
rsync -aHAX --numeric-ids "$SQQ"/ "$R"/
echo "==> copy เสร็จ: $(du -sh "$R" | cut -f1)"

# ลบ kernel 7.0 + firmware (ไม่ใช้กับ kernel 4.14 ตอนนี้ — ลดขนาดและเวลา build)
rm -rf "$R/usr/lib/modules" "$R/boot/vmlinuz"* "$R/boot/initrd.img"* "$R/boot/System.map"* "$R/boot/config"*
rm -rf "$R/usr/lib/firmware"
echo "==> ลบ kernel 7.0 + firmware เสร็จ: $(du -sh "$R" | cut -f1)"

# ---- 3. ติดตั้ง openssh-server (dpkg -x) ----
for D in "${SSH_DEBS[@]}"; do
  dpkg-deb -x "$D" "$R" && echo "  tar: $(basename "$D")"
done
ls -l "$R/usr/sbin/sshd" >/dev/null || { echo "ไม่มี sshd หลังแตก — หา openssh deb ตัวอื่น"; exit 1; }
echo "==> มี sshd แล้ว"

# ---- 4. ตั้งค่าด้านในผ่าน chroot (qemu) ----
cp /usr/bin/qemu-aarch64-static "$R/usr/bin/"
rm -f "$R/tmp/chroot-setup.sh"
mkdir -p "$R/tmp"
cat > "$R/tmp/chroot-setup.sh" <<'EOS'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# resolv.conf ชั่วคราว (ไม่ต้อง internet ใน chroot)
cp /etc/resolv.conf /etc/resolv.conf.orig 2>/dev/null || true
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# user dev (ตามของเดิม)
getent group sudo >/dev/null || groupadd -f sudo
id -u dev >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo dev
echo 'dev:ubuntu1234' | chpasswd
echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-dev
chmod 440 /etc/sudoers.d/90-dev

# hostname / hosts / fstab
echo sunny > /etc/hostname
printf '127.0.0.1 localhost\n127.0.1.1 sunny\n' > /etc/hosts
cat > /etc/fstab <<'FSTAB'
LABEL=sunny-root  /      ext4  defaults,noatime  0 1
tmpfs             /tmp   tmpfs defaults,nosuid  0 0
FSTAB

# timezone
ln -sf /usr/share/zoneinfo/Asia/Bangkok /etc/localtime
(echo "Asia/Bangkok" > /etc/timezone) 2>/dev/null || true

# ** watchdog ** — systemd เลี้ยง HW watchdog อัตโนมัติทุก 10 วิ
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/50-watchdog.conf <<'WD'
[Manager]
RuntimeWatchdogSec=10s
ShutdownWatchdogSec=10s
WD

# networkd: usb0 / rndis0 ทั้งคู่ (interface ชื่อไหนก็ได้ของ RNDIS ของ kernel 4.14)
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/10-rndis.network <<'NET'
[Match]
Name=usb0 rndis0
[Network]
Address=192.168.42.2/24
NET
systemctl enable systemd-networkd.service

# ssh
mkdir -p /etc/ssh/sshd_config.d
printf 'PasswordAuthentication yes\nPermitRootLogin no\n' > /etc/ssh/sshd_config.d/99-sunny.conf
ssh-keygen -A
systemctl enable ssh.service 2>/dev/null || systemctl enable sshd.service 2>/dev/null || true

# serial console ทาง ttyGS0 (ACM) เผื่อเข้าผ่าน COM เมื่อ net ไม่ได้
systemctl enable serial-getty@ttyGS0.service 2>/dev/null || true

# service ที่ไม่จำเป็นบนโทรศัพท์
systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true
systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
systemctl disable unattended-upgrades.service 2>/dev/null || true

# ---- USB gadget (configfs): ถ้า initramfs ตั้งไว้แล้ว → ข้ามไป (ไม่ rebind ซ้ำ) ----
mkdir -p /usr/local/sbin
cat > /usr/local/sbin/usb-gadget.sh <<'GADGET'
#!/bin/bash
# USB gadget RNDIS + ACM (กันยัดซ้ำถ้า initramfs ตั้งไว้แล้ว)
set -u
G=/sys/kernel/config/usb_gadget/g1
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config || exit 1
if [ -n "$(cat "$G/UDC" 2>/dev/null)" ]; then
  echo "gadget bound แล้ว (จาก initramfs) — ข้าม"
  exit 0
fi
i=0
while [ -z "$(ls /sys/class/udc 2>/dev/null)" ]; do
  i=$((i+1)); [ "$i" -gt 30 ] && { echo "UDC ไม่ขึ้น"; exit 1; }
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
  mkdir -p "$G/functions/rndis.usb0"
  mkdir -p "$G/functions/rndis.usb0/os_desc/interface.rndis" 2>/dev/null || true
  echo "RNDIS"    > "$G/functions/rndis.usb0/os_desc/interface.rndis/compatible_id"      2>/dev/null || true
  echo "5162001"  > "$G/functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id"  2>/dev/null || true
  ln -sf "$G/functions/rndis.usb0" "$G/configs/c.1/"
  if mkdir -p "$G/functions/acm.GS1" 2>/dev/null; then
    ln -sf "$G/functions/acm.GS1" "$G/configs/c.1/"
  fi
  echo 1        > "$G/os_desc/use"           2>/dev/null || true
  echo 0xcd     > "$G/os_desc/b_vendor_code" 2>/dev/null || true
  echo "MSFT100" > "$G/os_desc/qw_sign"      2>/dev/null || true
fi
echo "$UDC" > "$G/UDC" || { echo "UDC bind fail"; exit 1; }
echo "gadget bound → $UDC"
GADGET
chmod +x /usr/local/sbin/usb-gadget.sh

cat > /etc/systemd/system/usb-gadget.service <<'UNIT'
[Unit]
Description=USB gadget (RNDIS usb0 + ACM ttyGS0)
After=sysinit.target local-fs.target
Wants=sysinit.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/usb-gadget.sh
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
UNIT
systemctl enable usb-gadget.service

# ---- ขยาย rootfs ให้เต็ม userdata (พาร์ทิชัน ~100GB อย่างมาก) ----
cat > /usr/local/sbin/resize-rootfs.sh <<'RESIZE'
#!/bin/bash
set -u
DEV=$(findmnt -n -o SOURCE /)
[ -n "$DEV" ] || exit 1
resize2fs "$DEV" 2>/dev/null || true
exit 0
RESIZE
chmod +x /usr/local/sbin/resize-rootfs.sh

cat > /etc/systemd/system/resize-rootfs.service <<'UNIT2'
[Unit]
Description=Resize root filesystem to fill userdata
After=local-fs.target
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

# clean
rm -f /etc/resolv.conf.orig /var/lib/tmpfiles-d-backup 2>/dev/null || true
rm -rf /var/log/* /tmp/*
: > /var/log/lastlog 2>/dev/null || true
exit 0
EOS
chmod +x "$R/tmp/chroot-setup.sh"

cleanup() {
  for m in dev proc sys; do umount -l "$R/$m" 2>/dev/null || true; done
  rm -f "$R/usr/bin/qemu-aarch64-static"
}
trap cleanup EXIT
for m in proc sys dev; do mount --bind /$m "$R/$m"; done
chroot "$R" /usr/bin/qemu-aarch64-static /bin/bash /tmp/chroot-setup.sh
rm -f "$R/tmp/chroot-setup.sh"
# ลด bind mounts ออก "ก่อน" สร้างรูป — ไม่งั้น rsync จะ copy /proc/kcore ใหญ่มหึมาจน ENOSPC
for m in proc sys dev; do umount -l "$R/$m" 2>/dev/null || true; done
rm -f "$R/usr/bin/qemu-aarch64-static"

# ---- 5. สร้าง image แบบ mount-loop copy (ทนกว่า mke2fs -d บน WSL) ----
IMG="$OUT/rootfs.img"
umount -l /mnt/rootfs-new 2>/dev/null || true
rm -f "$IMG"
echo "==> สร้าง $IMG ($SIZE) แบบ loop-mount copy"
truncate -s "$SIZE" "$IMG"
mkfs.ext4 -q -F -L sunny-root "$IMG"
TM=/mnt/rootfs-new
mkdir -p "$TM"
mount -o loop "$IMG" "$TM"
rsync -aHAX --numeric-ids --exclude=/proc/** --exclude=/sys/** --exclude=/dev/** "$R"/ "$TM"/
sync
umount "$TM"
e2fsck -fy "$IMG" >/dev/null 2>&1 || true

# ---- 6. sparse + ส่งไป Windows ----
img2simg "$IMG" "$OUT/rootfs.simg"
for f in rootfs.img rootfs.simg; do
  [ -f "$OUT/$f" ] && cp "$OUT/$f" "/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out/$f" 2>/dev/null || true
done
ls -lh "$OUT/rootfs.img" "$OUT/rootfs.simg"
echo "เสร็จ: rootfs จาก ISO (label=sunny-root, user dev/ubuntu1234)"
