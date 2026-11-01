#!/usr/bin/env bash
# 04-probe-initramfs.sh — initramfs วินิจฉัย:
#   1) พ่น kernel log ของ "รอบก่อน" (pstore/ramoops) ออกทาง COM10  → เห็น panic trace
#   2) รันขั้นตอนของ sunny-init ทีละขั้น พร้อม marker PROBE> / PROBE<
#      + dmesg ท้ายทุกขั้น → รู้ว่าคำสั่งไหนฆ่าเครื่อง
#   3) ไม่รัน Ubuntu เต็มรูปแบบ (จะได้ไม่ตายก่อนเห็นข้อมูล)
#   ผลลัพธ์: out/initramfs-probe.cpio.gz + out/vendor_boot-probe.img
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
SUNNY="${SUNNY_ROOT:-/root/sunny}"
[ -d "$SUNNY/out" ] || SUNNY="$ROOT"
OUT="$SUNNY/out"
IR="$OUT/initramfs-probe"
BB="${BUSYBOX_AARCH64:-$OUT/busybox-aarch64}"
[ -f "$BB" ] || { echo "ต้องมี $BB"; exit 1; }
rm -rf "$IR"; mkdir -p "$IR/bin" "$IR/dev" "$IR/proc" "$IR/sys" "$IR/mnt"
cp "$BB" "$IR/bin/busybox"; chmod +x "$IR/bin/busybox"
file "$IR/bin/busybox" | grep -q 'ARM aarch64' || { echo "busybox ไม่ใช่ aarch64"; exit 1; }

cat > "$IR/init" <<'EOS'
#!/bin/busybox sh
/bin/busybox --install -s /bin
export PATH=/bin:/sbin
mount -t proc  proc  /proc
mount -t sysfs sys   /sys
mount -t devtmpfs dev /dev

say() { printf 'UBNT: %s\n' "$*"; printf 'UBNT: %s\n' "$*" > /dev/ttyGS0 2>/dev/null; return 0; }
kb()  { while IFS= read -r l; do printf 'KB| %s\n' "$l"; done; }

say "===== PROBE INITRAMFS ====="
say "cmdline: $(cat /proc/cmdline)"
say "panic timeout: $(cat /proc/sys/kernel/panic 2>/dev/null)"

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
echo "579a9d18"    > "$G/strings/0x409/serialnumber"
echo "sunny-probe" > "$G/strings/0x409/manufacturer"
echo "sunny probe" > "$G/strings/0x409/product"
echo "rndis" > "$G/configs/c.1/strings/0x409/configuration"
ln -sf "$G/functions/rndis.usb0" "$G/configs/c.1/" 2>/dev/null
ln -sf "$G/functions/acm.GS1"    "$G/configs/c.1/" 2>/dev/null
i=0
while [ -z "$(ls /sys/class/udc 2>/dev/null)" ]; do i=$((i+1)); [ "$i" -gt 60 ] && break; sleep 1; done
UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
if [ -n "$UDC" ]; then
  echo "$UDC" > "$G/UDC" 2>/dev/null
  say "gadget bound: $UDC"
  sleep 1
  IF=
  for n in $(ls /sys/class/net 2>/dev/null); do
    case "$n" in rndis*|usb0) IF="$n"; break ;; esac
  done
  if [ -n "$IF" ]; then
    ifconfig "$IF" 192.168.42.2 netmask 255.255.255.0 up 2>/dev/null
    ip route flush all 2>/dev/null
    ip route add 192.168.42.0/24 dev "$IF" scope link src 192.168.42.2 2>/dev/null
    say "net: $IF = 192.168.42.2/24"
  fi
  telnetd -l /bin/sh -p 23 2>/dev/null &
  say "telnet :23 พร้อม"
fi

# ---------- 1) KERNEL LOG ของรอบก่อน (panic!) ----------
say "===== PREV-BOOT KERNEL LOG ====="
FOUND=0
if [ -d /sys/fs/pstore ]; then
  for f in /sys/fs/pstore/*; do
    [ -f "$f" ] || continue
    FOUND=1
    say "pstore: $(basename "$f") size=$(wc -c < "$f")"
    tail -n 150 "$f" 2>/dev/null | kb
  done
fi
if [ -f /proc/last_kmsg ]; then
  FOUND=1
  say "last_kmsg size=$(wc -c < /proc/last_kmsg)"
  tail -n 150 /proc/last_kmsg 2>/dev/null | kb
fi
[ "$FOUND" = 0 ] && say "ไม่พบ pstore/last_kmsg (ramoops ไม่ลงทะเบียน?) — ls /sys/fs/pstore = $(ls /sys/fs/pstore 2>/dev/null | tr '\n' ' ')"
say "===== END PREV KERNEL LOG ====="

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
say "watchdog devices: $(ls /dev/watchdog* 2>/dev/null | tr '\n' ' ')"

# ---------- 2) หา + mount rootfs ----------
mdev -s 2>/dev/null
find_root() {
  [ -b /dev/block/by-name/userdata ] && { echo /dev/block/by-name/userdata; return; }
  for u in /sys/class/block/sd*/uevent /sys/class/block/mmcblk*/uevent; do
    [ -f "$u" ] || continue
    if grep -q '^PARTNAME=userdata$' "$u" 2>/dev/null; then
      d=$(basename "$(dirname "$u")"); [ -b "/dev/$d" ] && { echo "/dev/$d"; return; }
    fi
  done
  for d in /dev/sda17; do [ -b "$d" ] && { echo "$d"; return; }; done
}
RD=
i=0
while [ "$i" -lt 30 ]; do
  mdev -s 2>/dev/null; RD=$(find_root); [ -n "$RD" ] && break
  sleep 1; i=$((i+1))
done
say "rootfs = ${RD:-ไม่พบ}"
[ -n "$RD" ] && { mount -t ext4 -o rw,noatime "$RD" /mnt 2>/dev/null || say "mount ล้มเหลว"; }

if ! grep -q ' /mnt ' /proc/mounts; then
  say "ไม่มี rootfs — ค้างที่ heartbeat"
else
  say "rootfs mounted"
  mkdir -p /mnt/proc /mnt/sys /mnt/dev
  grep -q ' /mnt/proc ' /proc/mounts || mount --bind /proc /mnt/proc 2>/dev/null
  grep -q ' /mnt/sys '  /proc/mounts || mount --bind /sys  /mnt/sys  2>/dev/null
  grep -q ' /mnt/dev '  /proc/mounts || mount --bind /dev  /mnt/dev  2>/dev/null
  : > /mnt/probe.log

  # probe: 1 บรรทัด = 1 คำสั่ง, hasil ลง COM10
  probe() {
    NAME="$1"; shift
    printf 'PROBE> %s\n' "$NAME"
    printf 'PROBE> %s\n' "$NAME" >> /mnt/probe.log
    chroot /mnt /bin/sh -c "$*" >>/mnt/probe.log 2>&1
    RC=$?
    printf 'PROBE< %s rc=%s\n' "$NAME" "$RC"
    printf 'PROBE< %s rc=%s\n' "$NAME" "$RC" >> /mnt/probe.log
    dmesg 2>/dev/null | tail -n 3 | kb
  }

  probe baseline        'true'
  probe shell-ok        'echo SHELL_OK; id -u; cat /etc/os-release | head -2'
  probe var-write       'mkdir -p /var/log; echo VARWRITE_OK >> /var/log/probe.txt; echo VARWRITE_OK'
  probe tmp-dirs        'mkdir -p /dev/pts /dev/shm /run /run/lock /var/run /tmp; echo DIRS_OK'
  probe mount-devpts    'mount -t devpts devpts /dev/pts; grep devpts /proc/mounts'
  probe mount-devshm    'mount -t tmpfs tmpfs /dev/shm; grep shm /proc/mounts'
  probe mount-run       'mount -t tmpfs tmpfs /run; grep " /run " /proc/mounts'
  probe hostname        'echo sunny > /proc/sys/kernel/hostname; hostname'
  probe cgroup-cpu      'mount -t cgroup -o cpu cpu /sys/fs/cgroup/cpu; grep cpu /proc/mounts'
  probe cgroup-memory   'mount -t cgroup -o memory memory /sys/fs/cgroup/memory; echo MEMCG_OK'
  probe ip-up           'ip link set dev rndis0 up; ip addr flush dev rndis0; ip addr add 192.168.42.2/24 dev rndis0; ip -4 addr show rndis0'
  probe route-flush     'ip route flush all; ip route add 192.168.42.0/24 dev rndis0 scope link src 192.168.42.2; ip route'
  probe sshd-test       '/usr/sbin/sshd -t; echo SSHD_T_RC=$?'
  probe sshd-start      '/usr/sbin/sshd -o PidFile=/run/sshd.pid; sleep 1; cat /run/sshd.pid; ss -ltn 2>/dev/null | head -5'
  probe agetty          'ls -l /sbin/agetty /usr/sbin/agetty 2>&1; /sbin/agetty --version 2>&1 | head -1'
  probe ls-dev-tty      'ls -l /dev/tty0 /dev/ttyGS0 2>&1'

  say "PROBE จบครบทุกขั้น — ถ้าไม่ตาย = ปัญหาอยู่ที่ daemon ที่รันค้าง"
fi

# ---------- shell บน serial ----------
for TT in /dev/ttyGS0 /dev/ttyGS1; do
  if [ -e "$TT" ]; then
    setsid sh -c "exec sh -i <$TT >$TT 2>&1" &
    say "serial shell บน $TT"
    break
  fi
done

say "========== เข้า heartbeat =========="
n=0
while true; do
  n=$((n+1))
  printf 'UBNT: hb%d up=%ss\n' "$n" "$(cut -d. -f1 /proc/uptime)"
  sleep 10
done
EOS
chmod +x "$IR/init"

cd "$IR"
find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$OUT/initramfs-probe.cpio.gz"
echo "==> $OUT/initramfs-probe.cpio.gz ($(( $(stat -c%s "$OUT/initramfs-probe.cpio.gz") / 1024 )) KB)"

MK="$SUNNY/tools/mkbootimg/mkbootimg.py"
[ -f "$OUT/dtb" ] || { echo "ต้องมี $OUT/dtb"; exit 1; }
CMDLINE="console=tty0 console=ttyMSM0,115200n8 console=ttyGS0,115200n8 \
androidboot.hardware=qcom androidboot.usbcontroller=a600000.dwc3 loop.max_part=7 \
lpm_levels.sleep_disabled=1 service_locator.enable=1 swiotlb=1 msm_rtb.filter=0x237 kpti=off"
python3 "$MK" --header_version 4 \
  --vendor_boot "$OUT/vendor_boot-probe.img" \
  --vendor_ramdisk "$OUT/initramfs-probe.cpio.gz" \
  --dtb "$OUT/dtb" \
  --vendor_cmdline "$CMDLINE" \
  --os_version 16.0.0 --os_patch_level 2026-05 --pagesize 4096

cp "$OUT/vendor_boot-probe.img" "/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out/vendor_boot-probe.img" 2>/dev/null || true
ls -lh "$OUT/vendor_boot-probe.img"
sha256sum "$OUT/vendor_boot-probe.img"
echo "เสร็จ: vendor_boot-probe.img"
