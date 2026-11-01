#!/usr/bin/env bash
# 04-diag-initramfs.sh — initramfs โหมดวินิจฉัย: ห้าม switch_root เด็ดขาด
#   PID1 ค้างผ่าน shell + telnetd:23 + dmesg heartbeat ทุก 10 วิ
#   bash 04-diag-initramfs.sh  →  out/initramfs-diag.cpio.gz
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
OUT="${SUNNY_ROOT:-$ROOT}/out"
IR="$OUT/initramfs-diag"
BB="${BUSYBOX_AARCH64:-$OUT/busybox-aarch64}"
[ -f "$BB" ] || { echo "ต้องมี $BB — รัน 20-get-busybox-aarch64.sh ก่อน"; exit 1; }
rm -rf "$IR"; mkdir -p "$IR/bin" "$IR/dev" "$IR/proc" "$IR/sys" "$IR/mnt"
cp "$BB" "$IR/bin/busybox"
chmod +x "$IR/bin/busybox"
file "$IR/bin/busybox" | grep -q 'ARM aarch64' || { echo "✗ busybox ไม่ใช่ aarch64"; exit 1; }

cat > "$IR/init" <<'EOS'
#!/bin/busybox sh
/bin/busybox --install -s /bin
export PATH=/bin:/sbin
mount -t proc  proc  /proc
mount -t sysfs sys   /sys
mount -t devtmpfs dev /dev

mkdir /configfs 2>/dev/null
mount -t configfs none /configfs 2>/dev/null
if [ -d /configfs ]; then
  echo "DIAG: configfs ok"
  G=/configfs/usb_gadget/g1
  mkdir -p "$G" "$G/strings/0x409" "$G/configs/c.1/strings/0x409" "$G/functions/rndis.usb0" "$G/functions/acm.GS1" 2>/dev/null
  echo 0x1d6b > "$G/idVendor"
  echo 0x0104 > "$G/idProduct"
  echo 0x0100 > "$G/bcdDevice"
  echo 0x0200 > "$G/bcdUSB"
  echo "579a9d18"   > "$G/strings/0x409/serialnumber"
  echo "sunny-diag" > "$G/strings/0x409/manufacturer"
  echo "sunny diag" > "$G/strings/0x409/product"
  echo "rndis" > "$G/configs/c.1/strings/0x409/configuration"
  ln -sf "$G/functions/rndis.usb0" "$G/configs/c.1/" 2>/dev/null
  ln -sf "$G/functions/acm.GS1"    "$G/configs/c.1/" 2>/dev/null
  i=0
  while [ -z "$(ls /sys/class/udc 2>/dev/null)" ]; do
    i=$((i+1)); [ "$i" -gt 60 ] && break; sleep 1
  done
  UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
  if [ -n "$UDC" ]; then
    echo "$UDC" > "$G/UDC" 2>/dev/null && echo "DIAG: UDC=$UDC"
    sleep 1
    # บาง kernel ชื่อ interface ไม่ใช่ usb0 (อาจเป็น rndis0) — set ทุกตัวยกเว้น lo
    echo "DIAG: net ที่มี = $(ls /sys/class/net 2>/dev/null | tr '\n' ' ')"
    for IF in $(ls /sys/class/net 2>/dev/null); do
      [ "$IF" = "lo" ] && continue
      ifconfig "$IF" 192.168.42.2 netmask 255.255.255.0 up 2>/dev/null \
        && echo "DIAG: $IF = 192.168.42.2 up" \
        || echo "DIAG: $IF set ไม่ได้"
    done
    telnetd -l /bin/sh -p 23 2>/dev/null &
    echo "DIAG: telnetd on :23"
  else
    echo "DIAG: ไม่มี UDC!"
  fi
else
  echo "DIAG: configfs ไม่พบ!"
fi

# ---- ป้อน watchdog ทุก 5 วิ (กัน bootloader/kernel ตัดเครื่อง ~2 นาที) ----
W=
for wd in /dev/watchdog /dev/watchdog0 /dev/watchdog1; do
  [ -e "$wd" ] && { W="$wd"; break; }
done
if [ -n "$W" ]; then
  echo "DIAG: watchdog ที่พบ = $W — เริ่มป้อนทุก 5 วิ"
  (
    while :; do
      printf '1' > "$W" 2>/dev/null
      sleep 5
    done
  ) &
else
  echo "DIAG: ไม่เห็น /dev/watchdog*"
fi

mdev -s 2>/dev/null
i=0
while [ $i -lt 20 ]; do
  [ -e /dev/block/by-name/userdata ] && break
  mdev -s 2>/dev/null; sleep 2; i=$((i+1))
done
if [ -e /dev/block/by-name/userdata ]; then
  echo "DIAG: พบ userdata — mount แบบ ro (ไม่เข้า rootfs)"
  mount -t ext4 -o ro /dev/block/by-name/userdata /mnt 2>/dev/null && {
    echo "DIAG: mount ro OK"
    echo "--- /mnt ย่อ ---"
    ls /mnt 2>/dev/null
    echo "--- usb-gadget.sh (ถ้าใช่ตัวนี้ก์ที่ทำ USB หลุด) ---"
    sed -n 1,120p /mnt/usr/local/sbin/usb-gadget.sh 2>/dev/null
    echo "--- resize-rootfs.service ---"
    cat /mnt/etc/systemd/system/resize-rootfs.service 2>/dev/null
    echo "--- usb-gadget.service ---"
    cat /mnt/etc/systemd/system/usb-gadget.service 2>/dev/null
    umount /mnt 2>/dev/null
    echo "DIAG: umount แล้ว"
  } || echo "DIAG: mount rootfs ไม่ได้!"
else
  echo "DIAG: ไม่พบ userdata"
fi

echo "DIAG: อยู่ใน initramfs ตลอด — ไม่ switch_root"
echo "DIAG: telnet 192.168.42.2:23 + serial COM ทาง ttyGS0"

# ---- shell interactive บน serial (ttyGS0) — ทาง debug ที่บล็อกไม่ได้ ----
for TT in /dev/ttyGS0 /dev/ttyGS1; do
  if [ -e "$TT" ]; then
    setsid sh -c "exec sh -i <$TT >$TT 2>&1" &
    echo "DIAG: shell รอบน $TT (COM ฝั่ง PC เปิดจะคุยได้เลย)"
  fi
done

# ---- heartbeat: พิมพ์ทั้ง console และตรง ttyGS0 + บอก IP จริง ----
n=0
while true; do
  IPS=$(ip -4 addr show 2>/dev/null | grep -o 'inet 192.168.42.2' | head -1)
  LINE="DIAG: hb$[$n] up=$(cut -d. -f1 /proc/uptime)s ip=[${IPS:-ไม่มี!}]"
  echo "$LINE dmesg: $(dmesg 2>/dev/null | tail -1)"
  printf '%s\n' "$LINE" > /dev/ttyGS0 2>/dev/null
  n=$((n+1))
  sleep 10
done
EOS
chmod +x "$IR/init"

cd "$IR"
find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$OUT/initramfs-diag.cpio.gz"
ls -lh "$OUT/initramfs-diag.cpio.gz"
echo "เสร็จ: initramfs-diag (ไม่ switch_root เด็ดขาด)"
