#!/usr/bin/env bash
# 04-ubuntu-initramfs.sh — initramfs "ฐาน diag ที่พิสูจน์แล้ว" + สั่งบูต Ubuntu ใน chroot
#   หลักการ: PID1 = busybox ของ initramfs ตลอด (ไม่ switch_root → ไม่มีทาง panic loop)
#            telnet :23 + shell บน ttyGS0 ยังอยู่เสมอ แม้ Ubuntu จะพัง
#   ผลลัพธ์: out/initramfs-ubuntu.cpio.gz + out/vendor_boot-ubuntu.img
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
SUNNY="${SUNNY_ROOT:-/root/sunny}"
[ -d "$SUNNY/out" ] || SUNNY="$ROOT"
OUT="$SUNNY/out"
IR="$OUT/initramfs-ubuntu"
BB="${BUSYBOX_AARCH64:-$OUT/busybox-aarch64}"
[ -f "$BB" ] || { echo "ต้องมี $BB — รัน 20-get-busybox-aarch64.sh ก่อน"; exit 1; }

rm -rf "$IR"; mkdir -p "$IR/bin" "$IR/dev" "$IR/proc" "$IR/sys" "$IR/mnt"
cp "$BB" "$IR/bin/busybox"; chmod +x "$IR/bin/busybox"
file "$IR/bin/busybox" | grep -q 'ARM aarch64' || { echo "✗ busybox ไม่ใช่ aarch64"; exit 1; }

# sunny-init ฝังมากับ initramfs (แพตช์แล้วแฟลชแค่ vendor_boot)
sed 's/\r$//' "$HERE/sunny-init" > "$IR/sunny-init"
chmod 0755 "$IR/sunny-init"

cat > "$IR/init" <<'EOS'
#!/bin/busybox sh
/bin/busybox --install -s /bin
export PATH=/bin:/sbin
mount -t proc  proc  /proc
mount -t sysfs sys   /sys
mount -t devtmpfs dev /dev

say() {
  echo "UBNT: $*"
  [ -c /dev/ttyGS0 ] && printf 'UBNT: %s\n' "$*" > /dev/ttyGS0 2>/dev/null
  return 0
}

# ---------- USB gadget (RNDIS + ACM) ----------
mkdir /configfs 2>/dev/null
mount -t configfs none /configfs 2>/dev/null
G=/configfs/usb_gadget/g1
mkdir -p "$G" "$G/strings/0x409" "$G/configs/c.1/strings/0x409" \
         "$G/functions/rndis.usb0" "$G/functions/acm.GS1" 2>/dev/null
echo 0x1d6b > "$G/idVendor"
echo 0x0104 > "$G/idProduct"
echo 0x0100 > "$G/bcdDevice"
echo 0x0200 > "$G/bcdUSB"
echo "579a9d18"   > "$G/strings/0x409/serialnumber"
echo "sunny-ubuntu" > "$G/strings/0x409/manufacturer"
echo "sunny ubuntu" > "$G/strings/0x409/product"
echo "rndis" > "$G/configs/c.1/strings/0x409/configuration"
ln -sf "$G/functions/rndis.usb0" "$G/configs/c.1/" 2>/dev/null
ln -sf "$G/functions/acm.GS1"    "$G/configs/c.1/" 2>/dev/null

i=0
while [ -z "$(ls /sys/class/udc 2>/dev/null)" ]; do
  i=$((i+1)); [ "$i" -gt 60 ] && break; sleep 1
done
UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
if [ -n "$UDC" ]; then
  echo "$UDC" > "$G/UDC" 2>/dev/null
  say "gadget bound: $UDC"
  sleep 1
  # ตั้ง IP **เฉพาะ** interface ของ gadget (rndis*/usb0) — ห้ามตั้งทุกตัว (route ซ้อน ทำเน็ตพัง)
  IF=
  for n in $(ls /sys/class/net 2>/dev/null); do
    case "$n" in rndis*|usb0) IF="$n"; break ;; esac
  done
  if [ -n "$IF" ]; then
    ifconfig "$IF" 192.168.42.2 netmask 255.255.255.0 up 2>/dev/null
    ip route flush all 2>/dev/null
    ip route add 192.168.42.0/24 dev "$IF" scope link src 192.168.42.2 2>/dev/null
    say "net: $IF = 192.168.42.2/24"
  else
    say "net: ไม่เจอ rndis*/usb0 (มี: $(ls /sys/class/net | tr '\n' ' '))"
  fi
  telnetd -l /bin/sh -p 23 2>/dev/null &
  say "telnet :23 (shell ของ initramfs)"
else
  say "ไม่มี UDC!"
fi

# ---------- watchdog ----------
W=
for wd in /dev/watchdog /dev/watchdog0 /dev/watchdog1; do
  [ -e "$wd" ] && { W="$wd"; break; }
done
if [ -n "$W" ]; then
  ( while :; do printf '1' > "$W" 2>/dev/null; sleep 5; done ) &
  say "watchdog feed: $W"
else
  say "ไม่เห็น /dev/watchdog*"
fi

# ---------- หา rootfs: PARTNAME=userdata ----------
mdev -s 2>/dev/null
find_root() {
  [ -b /dev/block/by-name/userdata ] && { echo /dev/block/by-name/userdata; return; }
  for u in /sys/class/block/sd*/uevent /sys/class/block/mmcblk*/uevent; do
    [ -f "$u" ] || continue
    if grep -q '^PARTNAME=userdata$' "$u" 2>/dev/null; then
      d=$(basename "$(dirname "$u")")
      [ -b "/dev/$d" ] && { echo "/dev/$d"; return; }
    fi
  done
  for d in /dev/sda17; do [ -b "$d" ] && { echo "$d"; return; }; done
}
RD=
i=0
while [ "$i" -lt 30 ]; do
  mdev -s 2>/dev/null
  RD=$(find_root)
  [ -n "$RD" ] && break
  sleep 1; i=$((i+1))
done
say "rootfs = ${RD:-ไม่พบ}"

if [ -n "$RD" ]; then
  mount -t ext4 -o rw,noatime "$RD" /mnt 2>/dev/null || {
    say "mount rw ไม่ได้ — ลอง fsck"
    fsck -fy "$RD" >/dev/null 2>&1 || true
    mount -t ext4 -o rw,noatime "$RD" /mnt 2>/dev/null || say "mount ล้มเหลว"
  }
fi

if grep -q ' /mnt ' /proc/mounts; then
  say "rootfs mounted rw"
  # ---- โชว์ log ของ "รอบก่อน" บน serial (วินิจฉัยข้ามการรีบูต) ----
  if [ -f /mnt/var/log/sunny-init.log ]; then
    say "===== log ของรอบก่อน ====="
    tail -n 40 /mnt/var/log/sunny-init.log 2>/dev/null | while read -r l; do
      printf 'PREV| %s\n' "$l" > /dev/ttyGS0 2>/dev/null
    done
    say "===== จบ log รอบก่อน ====="
    mv /mnt/var/log/sunny-init.log /mnt/var/log/sunny-init.prev.log 2>/dev/null
  fi
  # อัปเดต sunny-init จาก initramfs
  if [ -f /sunny-init ] && [ -d /mnt/sbin ]; then
    cp /sunny-init /mnt/sbin/sunny-init 2>/dev/null && chmod 0755 /mnt/sbin/sunny-init
    say "sunny-init: md5 img=$(md5sum /sunny-init | cut -c1-8) root=$(md5sum /mnt/sbin/sunny-init | cut -c1-8)"
  fi
  # bind pseudo-fs เข้าไปใน chroot
  mkdir -p /mnt/proc /mnt/sys /mnt/dev
  grep -q ' /mnt/proc ' /proc/mounts || mount --bind /proc /mnt/proc 2>/dev/null
  grep -q ' /mnt/sys '  /proc/mounts || mount --bind /sys  /mnt/sys  2>/dev/null
  grep -q ' /mnt/dev '  /proc/mounts || mount --bind /dev  /mnt/dev  2>/dev/null

  # ทดสอบว่า shell ของ Ubuntu รันได้จริง
  say "test: $(chroot /mnt /bin/sh -c 'echo OK; id -u' 2>&1 | tr '\n' '/')"
  # เริ่ม Ubuntu (sshd + getty) — เบื้องหลัง, log เก็บไว้
  : > /tmp/ubuntu.log
  chroot /mnt /sbin/sunny-init >>/tmp/ubuntu.log 2>&1 &
  UPID=$!
  say "chroot sunny-init เริ่มแล้ว (pid=$UPID)"
fi

# ---------- shell บน serial (COM10) — ทาง debug ที่ไม่บล็อก ----------
for TT in /dev/ttyGS0 /dev/ttyGS1; do
  if [ -e "$TT" ]; then
    setsid sh -c "exec sh -i <$TT >$TT 2>&1" &
    say "serial shell บน $TT"
    break
  fi
done

# ---------- heartbeat + เก็บ log ของ Ubuntu มาโชว์บน serial ----------
n=0
while true; do
  if [ -s /tmp/ubuntu.log ]; then
    say "ubuntu-log: $(tail -n 4 /tmp/ubuntu.log | tr '\n' '|')"
    : > /tmp/ubuntu.log
  fi
  n=$((n+1))
  printf 'UBNT: hb%d up=%ss\n' "$n" "$(cut -d. -f1 /proc/uptime)" > /dev/ttyGS0 2>/dev/null
  sleep 10
done
EOS
chmod +x "$IR/init"

cd "$IR"
find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$OUT/initramfs-ubuntu.cpio.gz"
echo "==> $OUT/initramfs-ubuntu.cpio.gz ($(( $(stat -c%s "$OUT/initramfs-ubuntu.cpio.gz") / 1024 )) KB)"

# ---------- แพ็ก vendor_boot ----------
MK="$SUNNY/tools/mkbootimg/mkbootimg.py"
[ -f "$OUT/dtb" ] || { echo "ต้องมี $OUT/dtb"; exit 1; }
CMDLINE="console=tty0 console=ttyMSM0,115200n8 console=ttyGS0,115200n8 \
androidboot.hardware=qcom androidboot.usbcontroller=a600000.dwc3 loop.max_part=7 \
lpm_levels.sleep_disabled=1 service_locator.enable=1 swiotlb=1 msm_rtb.filter=0x237 kpti=off"
python3 "$MK" --header_version 4 \
  --vendor_boot "$OUT/vendor_boot-ubuntu.img" \
  --vendor_ramdisk "$OUT/initramfs-ubuntu.cpio.gz" \
  --dtb "$OUT/dtb" \
  --vendor_cmdline "$CMDLINE" \
  --os_version 16.0.0 --os_patch_level 2026-05 --pagesize 4096

cp "$OUT/vendor_boot-ubuntu.img" "/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out/vendor_boot-ubuntu.img" 2>/dev/null || true
ls -lh "$OUT/vendor_boot-ubuntu.img"
sha256sum "$OUT/vendor_boot-ubuntu.img"
echo "เสร็จ: vendor_boot-ubuntu.img (diag base + Ubuntu chroot)"
