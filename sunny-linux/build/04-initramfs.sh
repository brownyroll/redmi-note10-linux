#!/usr/bin/env bash
# 04-initramfs.sh — initramfs หา root (LABEL=sunny-root) แล้ว switch_root
#   bash 04-initramfs.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
OUT="${SUNNY_ROOT:-$ROOT}/out"
IR="$OUT/initramfs"
mkdir -p "$IR/bin" "$IR/sbin" "$IR/dev" "$IR/proc" "$IR/sys" "$IR/mnt"

# ---- busybox arm64 จริง (ต้องเป็น ELF aarch64 — armv8l ของ busybox.net = ELF 32-bit) ----
BB="${BUSYBOX_AARCH64:-$OUT/busybox-aarch64}"
if [ ! -f "$BB" ]; then
  echo "==> ดาวน์โหลด busybox-static arm64 จาก Ubuntu Ports"
  deb=$(curl -s http://ports.ubuntu.com/ubuntu-ports/dists/noble/main/binary-arm64/Packages.gz | gzip -dc | \
        awk '/^Package: busybox-static$/{f=1;next} f&&$1=="Filename:"{print $2; exit}')
  [ -n "$deb" ] || { echo "หา .deb ไม่เจอ"; exit 1; }
  curl -L --no-progress-meter -o "$OUT/busybox-static-arm64.deb" "http://ports.ubuntu.com/ubuntu-ports/$deb"
  dpkg-deb -x "$OUT/busybox-static-arm64.deb" "$OUT/.bbx"
  cp "$OUT/.bbx/bin/busybox" "$BB"
  rm -rf "$OUT/.bbx" "$OUT/busybox"
fi
cp "$BB" "$IR/bin/busybox"
chmod +x "$IR/bin/busybox"
file "$IR/bin/busybox" | grep -q 'ARM aarch64' || { echo "✗ busybox ไม่ใช่ aarch64"; exit 1; }
echo "✓ busybox = aarch64 จริง"
for a in sh mount umount mkdir cat sleep echo dmesg mdev switch_root ls ln; do
  ln -sf busybox "$IR/bin/$a"
done

# --- initramfs /init ต้องมี USB gadget ตั้งแต่วินาทีแรก ---
# เหตุผล: ถ้า kernel บูตแล้วไม่มีอะไรตอบสนอง (จอดำ) เราไม่รู้ว่า "ตายก่อน initramfs"
# หรือ "ตายตอน systemd" — ถ้า RNDIS/COM serial โผล่บน Windows = รอดถึง initramfs
# รวมถึง telnetd 192.168.42.2:23 ให้แอบดูสถานะแบบได้ไปมา
cat > "$IR/init" <<'EOS'
#!/bin/busybox sh
/bin/busybox --install -s /bin
export PATH=/bin:/sbin
mount -t proc  proc  /proc
mount -t sysfs sys   /sys
mount -t devtmpfs dev /dev
echo 0 > /proc/sys/kernel/printk 2>/dev/null || true

# ---- USB gadget ตั้งเร็วสุด (configfs) ----
mkdir /configfs 2>/dev/null
mount -t configfs none /configfs 2>/dev/null
if [ -d /configfs ]; then
  echo "initramfs: configfs ok"
  G=/configfs/usb_gadget/g1
  [ -d "$G" ] || {
    mkdir -p "$G" "$G/strings/0x409" "$G/configs/c.1/strings/0x409" "$G/functions/rndis.usb0"
    echo 0x1d6b > "$G/idVendor"
    echo 0x0104 > "$G/idProduct"
    echo 0x0100 > "$G/bcdDevice"
    echo 0x0200 > "$G/bcdUSB"
    echo 0xEF > "$G/bDeviceClass"
    echo 0x02 > "$G/bDeviceSubClass"
    echo 0x01 > "$G/bDeviceProtocol"
    echo "579a9d18"     > "$G/strings/0x409/serialnumber"
    echo "sunny-initramfs" > "$G/strings/0x409/manufacturer"
    echo "sunny rescue" > "$G/strings/0x409/product"
    echo "rndis" > "$G/configs/c.1/strings/0x409/configuration"
    echo 250 > "$G/configs/c.1/MaxPower"
    ln -sf "$G/functions/rndis.usb0" "$G/configs/c.1/"
    # ACM (ttyGS0) ถ้า kernel มี
    mkdir -p "$G/functions/acm.GS1" 2>/dev/null \
      && ln -sf "$G/functions/acm.GS1" "$G/configs/c.1/"
  }
  # รอ UDC จนถึง 45 วิ (dwc3 ควรพร้อมใน ~1-2 วิ)
  i=0
  while [ -z "$(ls /sys/class/udc 2>/dev/null)" ]; do
    i=$((i+1)); [ "$i" -gt 45 ] && break
    sleep 1
  done
  UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
  if [ -n "$UDC" ]; then
    echo "$UDC" > "$G/UDC" 2>/dev/null
    echo "initramfs: gadget bound to $UDC"
    sleep 1
    # **สำคัญ**: ตั้ง IP เฉพาะ interface ของ gadget (rndis*/usb0) เท่านั้น
    # ห้ามแตะ interface อื่น (ip6tnl0/sit0/ip_vti0 = มันสร้าง route ซ้อนทำ net โง่)
    NET=$(ls /sys/class/net 2>/dev/null | tr '\n' ' ')
    echo "initramfs: net = $NET"
    IFU=
    for IF in $(ls /sys/class/net 2>/dev/null); do
      case "$IF" in rndis*|usb0) IFU="$IF"; break ;; esac
    done
    if [ -n "$IFU" ]; then
      ifconfig "$IFU" 192.168.42.2 netmask 255.255.255.0 up 2>/dev/null \
        && echo "initramfs: $IFU = 192.168.42.2 up (route dev $IFU)"
      ip route show | grep "$IFU" 2>/dev/null
    else
      echo "initramfs: ไม่เจอ interface gadget (rndis*/usb0)"
    fi
    telnetd -l /bin/sh -p 23 2>/dev/null &
    echo "initramfs: telnetd on :23 (rescue)"
  else
    echo "initramfs: ไม่พบ UDC — dwc3 ยังไม่พร้อม (ต้องจับที่ kernel เอง)"
  fi
fi

# ---- ป้อน watchdog ทุก 5 วิ กันเครื่องรีบูตเองระหว่างบูต ----
W=
for wd in /dev/watchdog /dev/watchdog0 /dev/watchdog1; do
  [ -e "$wd" ] && { W="$wd"; break; }
done
if [ -n "$W" ]; then
  echo "initramfs: watchdog feed ที่ $W ทุก 5 วิ"
  (
    while :; do
      printf '1' > "$W" 2>/dev/null
      sleep 5
    done
  ) &
else
  echo "initramfs: ไม่เห็น /dev/watchdog*"
fi

# ---- หา root device ----
# kernel 4.14 ตัวนี้ไม่มี /dev/block/by-name/* (ไม่มี ueventd/uevent helper)
# UFS โผล่เป็น /dev/sdaN และชื่อพาร์ทิชันอยู่ใน /sys/class/block/<dev>/uevent = PARTNAME=
find_root() {
  # 1) by-name ถ้ามี
  [ -b /dev/block/by-name/userdata ] && { echo /dev/block/by-name/userdata; return; }
  # 2) ค้น PARTNAME=userdata ใน sysfs (แม่นสุด)
  for u in /sys/class/block/sd*/uevent /sys/class/block/mmcblk*/uevent; do
    [ -f "$u" ] || continue
    if grep -q '^PARTNAME=userdata$' "$u" 2>/dev/null; then
      d=$(basename "$(dirname "$u")")
      [ -b "/dev/$d" ] && { echo "/dev/$d"; return; }
    fi
  done
  # 3) fallback ที่รู้จากเครื่องจริง
  for d in /dev/sda17 /dev/sda21 /dev/mmcblk0p*/userdata; do
    [ -b "$d" ] && { echo "$d"; return; }
  done
}

mdev -s
i=0
ROOTDEV=
while [ $i -lt 60 ]; do
  mdev -s
  ROOTDEV=$(find_root)
  [ -n "$ROOTDEV" ] && break
  sleep 1; i=$((i+1))
done

if [ -z "$ROOTDEV" ] || [ ! -b "$ROOTDEV" ]; then
  echo "!!! ไม่พบพาร์ทิชัน userdata — rescue บน telnet(192.168.42.2) / ttyGS0 / ttyMSM0"
  ls /dev | tr '\n' ' '
  echo
  exec sh
fi
echo "initramfs: rootdev = $ROOTDEV"

echo "mount root: $ROOTDEV"
fsck -fy "$ROOTDEV" 2>/dev/null || true
mount -t ext4 -o rw,noatime "$ROOTDEV" /mnt || {
  echo "!!! mount ไม่ได้ (อาจยัง fsck ไม่ผ่าน) — rescue shell"
  exec sh
}
[ -x /mnt/lib/systemd/systemd ] || { echo "!!! rootfs ไม่มี systemd"; exec sh; }

# อัปเดต sunny-init ใน rootfs จากสำเนาที่มากับ initramfs (ไม่ต้องแฟลช userdata ใหม่)
if [ -f /sunny-init ] && [ -d /mnt/sbin ]; then
  cp /sunny-init /mnt/sbin/sunny-init 2>/dev/null && chmod 0755 /mnt/sbin/sunny-init
  echo "initramfs: อัปเดต /mnt/sbin/sunny-init จาก initramfs"
fi

# ---- เลือกโหมด: sunny.mode=chroot (ค่าเริ่มต้น) หรือ sunny.mode=switch ----
MODE=chroot
for a in $(cat /proc/cmdline); do
  case "$a" in sunny.mode=*) MODE="${a#sunny.mode=}" ;; esac
done
echo "initramfs: mode=$MODE"

say() {
  echo "initramfs: $*"
  [ -c /dev/ttyGS0 ] && printf 'initramfs: %s\n' "$*" > /dev/ttyGS0 2>/dev/null
  return 0
}

if [ "$MODE" = "switch" ]; then
  mkdir -p /mnt/proc /mnt/sys /mnt/dev /mnt/configfs
  mount --move /proc /mnt/proc 2>/dev/null
  mount --move /sys  /mnt/sys  2>/dev/null
  mount --move /dev  /mnt/dev  2>/dev/null
  mount --move /configfs /mnt/configfs 2>/dev/null
  if [ -x /mnt/sbin/sunny-init ]; then
    echo "initramfs: switch_root → /sbin/sunny-init"
    exec switch_root /mnt /sbin/sunny-init
  fi
  echo "initramfs: switch_root → systemd"
  exec switch_root /mnt /lib/systemd/systemd
fi

# ---- โหมด chroot (ปลอดภัย): initramfs ยังเป็น PID1, telnet 23 / ttyGS0 ยังใช้ได้เสมอ ----
is_mnt() { grep -q " $1 " /proc/mounts 2>/dev/null; }
mkdir -p /mnt/proc /mnt/sys /mnt/dev /mnt/configfs
is_mnt /mnt/proc || mount --bind /proc /mnt/proc 2>/dev/null
is_mnt /mnt/sys  || mount --bind /sys  /mnt/sys  2>/dev/null
is_mnt /mnt/dev  || mount --bind /dev  /mnt/dev  2>/dev/null
if [ -d /configfs/usb_gadget ]; then
  is_mnt /mnt/configfs || mount --bind /configfs /mnt/configfs 2>/dev/null
fi

CHINIT=/mnt/sbin/sunny-init
[ -x "$CHINIT" ] || CHINIT=/mnt/lib/systemd/systemd
say "check: /bin/sh=$([ -x /mnt/bin/sh ] && echo ok || echo MISSING) sunny-init=$([ -x /mnt/sbin/sunny-init ] && echo ok || echo MISSING)"

if [ -x /mnt/bin/sh ]; then
  COUT=$(chroot /mnt /bin/sh -c 'echo CHROOT_SHELL_OK; id -u; pwd' 2>&1)
  say "chroot test: $(echo "$COUT" | tr '\n' '/')"
fi
if [ -f /sunny-init ] && [ -f /mnt/sbin/sunny-init ]; then
  say "sunny-init md5: img=$(md5sum /sunny-init | cut -c1-8) root=$(md5sum /mnt/sbin/sunny-init | cut -c1-8)"
fi

# ---- serial shell บน ttyGS0 (ไว้ debug สด ๆ ผ่าน COM) ----
if [ -c /dev/ttyGS0 ]; then
  ( setsid sh -c 'exec sh </dev/ttyGS0 >/dev/ttyGS0 2>&1' ) >/dev/null 2>&1 &
  say "serial shell พร้อมบน ttyGS0"
fi

say "chroot mode: start $CHINIT"
: > /tmp/cinit.log
chroot /mnt "$CHINIT" >>/tmp/cinit.log 2>&1 &
CPID=$!

while :; do
  sleep 15
  if [ -s /tmp/cinit.log ]; then
    say "chroot-log: $(tail -n 6 /tmp/cinit.log | tr '\n' '|')"
    : > /tmp/cinit.log
  fi
  if ! kill -0 "$CPID" 2>/dev/null; then
    say "chroot init exited (rc unknown) — restart"
    chroot /mnt "$CHINIT" >>/tmp/cinit.log 2>&1 &
    CPID=$!
  fi
done
EOS
chmod +x "$IR/init"

# ---- ฝัง sunny-init มากับ initramfs (แก้แล้วแฟลชแค่ vendor_boot) ----
if [ -f "$HERE/sunny-init" ]; then
  sed 's/\r$//' "$HERE/sunny-init" > "$IR/sunny-init"
  chmod 0755 "$IR/sunny-init"
  echo "✓ sunny-init ฝังใน initramfs ($(wc -c < "$IR/sunny-init") bytes)"
fi

# ---- แพ็ก ----
cd "$IR"
find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$OUT/initramfs.cpio.gz"
SIZE=$(stat -c%s "$OUT/initramfs.cpio.gz")
echo "==> $OUT/initramfs.cpio.gz  ($((SIZE/1024)) KB)"
if [ "$SIZE" -gt 94371840 ]; then
  echo "⚠️  ใหญ่เกิน 90 MB (vendor_boot มี 96 MB) — ลด module/busybox"
fi
