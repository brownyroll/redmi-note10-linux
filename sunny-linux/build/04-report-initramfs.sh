#!/usr/bin/env bash
# 04-report-initramfs.sh — initramfs ที่ "รายงานผลออกมาได้" แม้เครื่องจะรีเซ็ต
#   - เปิด HTTP :80 บนเครื่อง → Windows ดึง http://192.168.42.2/current.log ได้
#   - เขียน log ลง rootfs (/mnt/report.log) + sync ทุกขั้น → รอดข้ามการรีบูต
#   - รอบถัดไปจะเสิร์ฟ log ของรอบก่อนที่ /prevboot.log อัตโนมัติ
#   - สุดท้ายรัน sunny-init ตัวจริงด้วย `sh -x` + sync ต่อเนื่อง → เห็นคำสั่งสุดท้ายก่อนตาย
#   ผลลัพธ์: out/initramfs-report.cpio.gz + out/vendor_boot-report.img
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
SUNNY="${SUNNY_ROOT:-/root/sunny}"
[ -d "$SUNNY/out" ] || SUNNY="$ROOT"
OUT="$SUNNY/out"
IR="$OUT/initramfs-report"
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

# ---------- USB gadget ----------
mkdir /configfs 2>/dev/null
mount -t configfs none /configfs 2>/dev/null
G=/configfs/usb_gadget/g1
mkdir -p "$G" "$G/strings/0x409" "$G/configs/c.1/strings/0x409" \
         "$G/functions/rndis.usb0" "$G/functions/acm.GS1" 2>/dev/null
echo 0x1d6b > "$G/idVendor"
echo 0x0104 > "$G/idProduct"
echo 0x0100 > "$G/bcdDevice"
echo 0x0200 > "$G/bcdUSB"
echo "579a9d18"     > "$G/strings/0x409/serialnumber"
echo "sunny-report" > "$G/strings/0x409/manufacturer"
echo "sunny report" > "$G/strings/0x409/product"
echo "rndis" > "$G/configs/c.1/strings/0x409/configuration"
ln -sf "$G/functions/rndis.usb0" "$G/configs/c.1/" 2>/dev/null
ln -sf "$G/functions/acm.GS1"    "$G/configs/c.1/" 2>/dev/null
i=0
while [ -z "$(ls /sys/class/udc 2>/dev/null)" ]; do i=$((i+1)); [ "$i" -gt 60 ] && break; sleep 1; done
UDC=$(ls /sys/class/udc 2>/dev/null | head -1)
if [ -n "$UDC" ]; then
  echo "$UDC" > "$G/UDC" 2>/dev/null
  sleep 1
  IF=
  for n in $(ls /sys/class/net 2>/dev/null); do
    case "$n" in rndis*|usb0) IF="$n"; break ;; esac
  done
  if [ -n "$IF" ]; then
    ifconfig "$IF" 192.168.42.2 netmask 255.255.255.0 up 2>/dev/null
    ip route flush all 2>/dev/null
    ip route add 192.168.42.0/24 dev "$IF" scope link src 192.168.42.2 2>/dev/null
  fi
  telnetd -l /bin/sh -p 23 2>/dev/null &
fi

# ---------- watchdog ทันที (ก่อนอย่างอื่น) ----------
for wd in /dev/watchdog /dev/watchdog0 /dev/watchdog1; do
  if [ -e "$wd" ]; then
    ( while :; do printf '1' > "$wd" 2>/dev/null; sleep 5; done ) &
    break
  fi
done

# ---------- rootfs ----------
mdev -s 2>/dev/null
find_root() {
  [ -b /dev/block/by-name/userdata ] && { echo /dev/block/by-name/userdata; return; }
  for u in /sys/class/block/sd*/uevent /sys/class/block/mmcblk*/uevent; do
    [ -f "$u" ] || continue
    if grep -q '^PARTNAME=userdata$' "$u" 2>/dev/null; then
      d=$(basename "$(dirname "$u")"); [ -b "/dev/$d" ] && { echo "/dev/$d"; return; }
    fi
  done
  [ -b /dev/sda17 ] && echo /dev/sda17
}
RD=
i=0
while [ "$i" -lt 40 ]; do
  mdev -s 2>/dev/null; RD=$(find_root); [ -n "$RD" ] && break
  sleep 1; i=$((i+1))
done
say "rootfs=${RD:-none}"
[ -n "$RD" ] && mount -t ext4 -o rw,noatime "$RD" /mnt 2>/dev/null

WWW=/tmp/www; mkdir -p "$WWW"
LOG="$WWW/current.log"; PLOG=/mnt/report.log
: > "$LOG" 2>/dev/null

rep() {
  printf '%s\n' "$*" >> "$LOG" 2>/dev/null
  printf '%s\n' "$*" >> "$PLOG" 2>/dev/null
  say "$*"
}
if grep -q ' /mnt ' /proc/mounts; then
  mkdir -p "$WWW"
  if [ -s /mnt/report.log ] && [ "$(wc -c < /mnt/report.log)" -gt 0 ]; then
    cp /mnt/report.log "$WWW/prevboot.log" 2>/dev/null
  fi
  if [ -s /mnt/sunnyx.log ]; then cp /mnt/sunnyx.log "$WWW/prev-sunnyx.log" 2>/dev/null; fi
  : > /mnt/report.log
  : > /mnt/sunnyx.log
  # serve ทันที ไม่ต้องรออย่างอื่น
  httpd -p 80 -h "$WWW" 2>/dev/null &
  rep "httpd :80 serving $WWW"
fi

rep "===== REPORT BOOT up=$(cut -d. -f1 /proc/uptime)s ====="
rep "cmdline: $(cat /proc/cmdline)"
rep "panic=$(cat /proc/sys/kernel/panic 2>/dev/null) watchdog=$(ls /dev/watchdog* 2>/dev/null | tr '\n' ' ')"
rep "pstore: $(ls /sys/fs/pstore 2>/dev/null | tr '\n' ' ') last_kmsg=$([ -f /proc/last_kmsg ] && echo yes || echo no)"

# ---------- kernel log ของรอบก่อน ----------
for f in /sys/fs/pstore/*; do
  [ -f "$f" ] || continue
  rep "--- pstore $(basename "$f") size=$(wc -c < "$f") ---"
  tail -n 200 "$f" 2>/dev/null >> "$LOG"
done
[ -f /proc/last_kmsg ] && tail -n 200 /proc/last_kmsg >> "$LOG" 2>/dev/null
sync 2>/dev/null
rep "--- dmesg current (tail 60) ---"
dmesg 2>/dev/null | tail -n 60 >> "$LOG"
sync 2>/dev/null

# ---------- probe ทีละขั้น ----------
if grep -q ' /mnt ' /proc/mounts; then
  mkdir -p /mnt/proc /mnt/sys /mnt/dev
  grep -q ' /mnt/proc ' /proc/mounts || mount --bind /proc /mnt/proc 2>/dev/null
  grep -q ' /mnt/sys '  /proc/mounts || mount --bind /sys  /mnt/sys  2>/dev/null
  grep -q ' /mnt/dev '  /proc/mounts || mount --bind /dev  /mnt/dev  2>/dev/null

  probe() {
    NAME="$1"; shift
    rep "PROBE> $NAME"
    sync 2>/dev/null
    OUTP=$(chroot /mnt /bin/sh -c "$*" 2>&1)
    RC=$?
    printf '%s\n' "$OUTP" >> "$LOG" 2>/dev/null
    rep "PROBE< $NAME rc=$RC"
    sync 2>/dev/null
    dmesg 2>/dev/null | tail -n 2 >> "$LOG"
  }

  probe baseline      'true'
  probe shell-ok      'echo SHELL_OK; id -u; head -2 /etc/os-release'
  probe var-write     'mkdir -p /var/log; echo V_OK >> /var/log/probe.txt; echo V_OK'
  probe mkdirs        'mkdir -p /dev/pts /dev/shm /run /run/lock /var/run /tmp; echo DIRS_OK'
  probe mount-devpts  'mount -t devpts devpts /dev/pts; grep -c devpts /proc/mounts'
  probe mount-devshm  'mount -t tmpfs tmpfs /dev/shm; echo SHM_OK'
  probe mount-run     'mount -t tmpfs tmpfs /run; grep -c " /run " /proc/mounts'
  probe chmod         'chmod 1777 /tmp /dev/shm; echo CHMOD_OK'
  probe hostname      'echo sunny > /proc/sys/kernel/hostname; hostname'
  probe cg-cpu        'mount -t cgroup -o cpu cpu /sys/fs/cgroup/cpu; echo CGCPU_OK'
  probe cg-mem        'mount -t cgroup -o memory memory /sys/fs/cgroup/memory; echo CGMEM_OK'
  probe ip-cmds       'ip link set dev rndis0 up; ip addr flush dev rndis0; ip addr add 192.168.42.2/24 dev rndis0; ip -4 addr show rndis0 | head -4'
  probe route-cmds    'ip route flush all; ip route add 192.168.42.0/24 dev rndis0 scope link src 192.168.42.2; ip route | head -4'
  probe sshd-test     '/usr/sbin/sshd -t; echo SSHD_T=$?'
  probe agetty-check  'ls -l /sbin/agetty /usr/sbin/agetty 2>&1 | head -3'
  rep "===== PROBE DONE ====="
  sync 2>/dev/null

  # ---------- รัน sunny-init ตัวจริงแบบ xtrace + sync ต่อเนื่อง ----------
  ( while :; do sync 2>/dev/null; sleep 2; done ) &
  rep "===== RUN REAL sunny-init (sh -x) ====="
  sync 2>/dev/null
  chroot /mnt /bin/sh -x /sbin/sunny-init >>/mnt/sunnyx.log 2>&1 &
  UPID=$!
  rep "sunny-init pid=$UPID"
fi

# ---------- heartbeat (เขียนลง log ด้วย) ----------
n=0
while true; do
  n=$((n+1))
  printf 'HB n=%s up=%ss sunny-init=%s\n' "$n" "$(cut -d. -f1 /proc/uptime)" "$(kill -0 ${UPID:-0} 2>/dev/null && echo alive || echo dead)" >> "$LOG" 2>/dev/null
  sync 2>/dev/null
  printf 'UBNT: hb%s up=%ss\n' "$n" "$(cut -d. -f1 /proc/uptime)"
  sleep 10
done
EOS
chmod +x "$IR/init"

cd "$IR"
find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$OUT/initramfs-report.cpio.gz"
echo "==> $OUT/initramfs-report.cpio.gz ($(( $(stat -c%s "$OUT/initramfs-report.cpio.gz") / 1024 )) KB)"

MK="$SUNNY/tools/mkbootimg/mkbootimg.py"
[ -f "$OUT/dtb" ] || { echo "ต้องมี $OUT/dtb"; exit 1; }
CMDLINE="console=tty0 console=ttyMSM0,115200n8 console=ttyGS0,115200n8 \
androidboot.hardware=qcom androidboot.usbcontroller=a600000.dwc3 loop.max_part=7 \
lpm_levels.sleep_disabled=1 service_locator.enable=1 swiotlb=1 msm_rtb.filter=0x237 kpti=off"
python3 "$MK" --header_version 4 \
  --vendor_boot "$OUT/vendor_boot-report.img" \
  --vendor_ramdisk "$OUT/initramfs-report.cpio.gz" \
  --dtb "$OUT/dtb" \
  --vendor_cmdline "$CMDLINE" \
  --os_version 16.0.0 --os_patch_level 2026-05 --pagesize 4096

cp "$OUT/vendor_boot-report.img" "/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out/vendor_boot-report.img" 2>/dev/null || true
ls -lh "$OUT/vendor_boot-report.img"
sha256sum "$OUT/vendor_boot-report.img"
echo "เสร็จ: vendor_boot-report.img"
