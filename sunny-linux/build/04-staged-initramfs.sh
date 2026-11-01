#!/usr/bin/env bash
# 04-staged-initramfs.sh — initramfs ที่ "ทดลองเองทีละขั้น ข้ามการรีบูต"
#   * เก็บ stage counter + log ไว้บนพาร์ทิชัน cache (ext4 เล็ก) → รอดข้ามรีบูต
#     โดยไม่ต้องพึ่ง userdata (ถ้า userdata rw mount เป็นตัวฆ่าเครื่อง เราจะรู้และยังได้ log)
#   * ทุก stage: เปิด HTTP :80 เสิร์ฟ /tmp/www (current.log + log ของ stage ก่อน ๆ)
#   * จบ stage แล้ว reboot เอง → stage ถัดไป
#   stages: 0 baseline | 1 userdata ro | 2 userdata rw | 3 chroot sh
#           4 chroot sunny-init (sh -x) | 5 sshd เท่านั้น
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
SUNNY="${SUNNY_ROOT:-/root/sunny}"
[ -d "$SUNNY/out" ] || SUNNY="$ROOT"
OUT="$SUNNY/out"
IR="$OUT/initramfs-staged"
BB="${BUSYBOX_AARCH64:-$OUT/busybox-aarch64}"
[ -f "$BB" ] || { echo "ต้องมี $BB"; exit 1; }
rm -rf "$IR"; mkdir -p "$IR/bin" "$IR/dev" "$IR/proc" "$IR/sys" "$IR/mnt" "$IR/cache"
cp "$BB" "$IR/bin/busybox"; chmod +x "$IR/bin/busybox"
file "$IR/bin/busybox" | grep -q 'ARM aarch64' || { echo "busybox ไม่ใช่ aarch64"; exit 1; }

cat > "$IR/init" <<'EOS'
#!/bin/busybox sh
/bin/busybox --install -s /bin
export PATH=/bin:/sbin
mount -t proc  proc  /proc
mount -t sysfs sys   /sys
mount -t devtmpfs dev /dev

say() { printf 'STG %s\n' "$*"; printf 'STG %s\n' "$*" > /dev/ttyGS0 2>/dev/null; return 0; }

# ---------------- USB gadget ----------------
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
echo "sunny-staged" > "$G/strings/0x409/manufacturer"
echo "sunny staged" > "$G/strings/0x409/product"
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
    say "net $IF ok"
  fi
  telnetd -l /bin/sh -p 23 2>/dev/null &
fi

# ---------------- watchdog ----------------
for wd in /dev/watchdog /dev/watchdog0 /dev/watchdog1; do
  if [ -e "$wd" ]; then
    ( while :; do printf '1' > "$wd" 2>/dev/null; sleep 5; done ) &
    break
  fi
done

# ---------------- httpd บน tmpfs ----------------
mkdir -p /tmp/www
mount -t tmpfs tmpfs /tmp/www 2>/dev/null
WWW=/tmp/www
LOG="$WWW/current.log"
: > "$LOG"
rep() { printf '%s\n' "$*" >> "$LOG" 2>/dev/null; say "$*"; }
httpd -p 80 -h "$WWW" 2>/dev/null &
rep "httpd :80 up"

# ---------------- หาพาร์ทิชัน ----------------
mdev -s 2>/dev/null
find_part() {
  for u in /sys/class/block/*/uevent; do
    [ -f "$u" ] || continue
    if grep -q "^PARTNAME=$1$" "$u" 2>/dev/null; then
      basename "$(dirname "$u")"; return 0
    fi
  done
  return 1
}
i=0
while [ $i -lt 20 ]; do
  UD=$(find_part userdata); [ -n "${UD:-}" ] && break
  mdev -s 2>/dev/null; sleep 1; i=$((i+1))
done
CA=$(find_part cache)
rep "parts: userdata=/dev/${UD:-none} cache=/dev/${CA:-none}"

# ---------------- stage counter บน cache ----------------
STAGE=0
CACHE_OK=no
if [ -n "${CA:-}" ]; then
  if mount -t ext4 -o rw,noatime "/dev/$CA" /cache 2>/dev/null; then
    CACHE_OK=yes
    mkdir -p /cache/sunny 2>/dev/null
    [ -f /cache/sunny/stage ] && STAGE=$(cat /cache/sunny/stage 2>/dev/null)
    case "${STAGE:-x}" in ''|*[!0-9]*) STAGE=0 ;; esac
  fi
fi
rep "STAGE=$STAGE cache_rw=$CACHE_OK"
SLOG=/dev/null
if [ "$CACHE_OK" = yes ]; then
  SLOG=/cache/sunny/stage$STAGE.log
  : > "$SLOG" 2>/dev/null
  printf '%s' "$((STAGE+1))" > /cache/sunny/stage 2>/dev/null
  sync
  for f in /cache/sunny/stage*.log; do [ -f "$f" ] && cp "$f" "$WWW/" 2>/dev/null; done
fi
srep() {
  printf '%s\n' "$*" >> "$LOG" 2>/dev/null
  [ "$SLOG" != /dev/null ] && printf '%s\n' "$*" >> "$SLOG" 2>/dev/null
  say "$*"
}

# ---------------- ข้อมูลพื้นฐาน ----------------
srep "cmdline: $(cat /proc/cmdline)"
srep "panic=$(cat /proc/sys/kernel/panic 2>/dev/null) wd=$(ls /dev/watchdog* 2>/dev/null | tr '\n' ' ')"
srep "pstore: $(ls /sys/fs/pstore 2>/dev/null | tr '\n' ' ') last_kmsg=$([ -f /proc/last_kmsg ] && echo yes || echo no)"
srep "parts: $(cat /proc/partitions | tr '\n' ';' | cut -c1-400)"
for f in /sys/fs/pstore/*; do
  [ -f "$f" ] || continue
  srep "--- pstore $(basename "$f") size=$(wc -c < "$f") ---"
  tail -n 250 "$f" 2>/dev/null >> "$LOG"
  [ "$SLOG" != /dev/null ] && tail -n 250 "$f" 2>/dev/null >> "$SLOG"
done
[ -f /proc/last_kmsg ] && { srep "--- last_kmsg ---"; tail -n 250 /proc/last_kmsg >> "$LOG" 2>/dev/null; }
srep "--- dmesg ---"
dmesg 2>/dev/null | tail -n 60 >> "$LOG"
[ "$SLOG" != /dev/null ] && dmesg 2>/dev/null | tail -n 60 >> "$SLOG"
sync

# ---------------- ให้เวลาโฮสต์ดึง log (40 วิ) ----------------
rep "serving 40s ... stage $STAGE"
n=0
while [ $n -lt 40 ]; do
  n=$((n+1))
  printf 'STAGE=%s up=%ss serve=%s/40\n' "$STAGE" "$(cut -d. -f1 /proc/uptime)" "$n" >> "$LOG"
  sync 2>/dev/null
  sleep 1
done

# ---------------- ทำงานตาม stage ----------------
DOSYNC() { ( while :; do sync 2>/dev/null; sleep 2; done ) & }
case "$STAGE" in
0)
  srep "stage0: baseline (ไม่แตะ userdata)"
  ;;
1)
  srep "stage1: mount userdata RO"
  if mount -t ext4 -o ro "/dev/$UD" /mnt 2>/dev/null; then
    srep "mount ro OK: $(ls /mnt | tr '\n' ' ' | cut -c1-300)"
    srep "os-release: $(head -2 /mnt/etc/os-release 2>/dev/null | tr '\n' ' ')"
    umount /mnt 2>/dev/null
    srep "umount ro OK"
  else
    srep "mount ro FAILED rc=$?"
  fi
  ;;
2)
  srep "stage2: mount userdata RW + เขียนไฟล์"
  if mount -t ext4 -o rw,noatime "/dev/$UD" /mnt 2>/dev/null; then
    srep "mount rw OK"
    echo "rwtest $(date -u +%s)" > /mnt/rwtest.txt 2>&1
    srep "write rwtest rc=$?"
    sync
    srep "sync done"
    umount /mnt 2>/dev/null
    srep "umount rw rc=$?"
  else
    srep "mount rw FAILED rc=$?"
  fi
  ;;
3)
  srep "stage3: chroot shell"
  if mount -t ext4 -o rw,noatime "/dev/$UD" /mnt 2>/dev/null; then
    mkdir -p /mnt/proc /mnt/sys /mnt/dev
    mount --bind /proc /mnt/proc 2>/dev/null
    mount --bind /sys  /mnt/sys  2>/dev/null
    mount --bind /dev  /mnt/dev  2>/dev/null
    R=$(chroot /mnt /bin/sh -c 'echo CHROOT_OK; id -u; head -1 /etc/os-release' 2>&1)
    srep "chroot rc=$? out=$(printf '%s' "$R" | tr '\n' '/')"
  else
    srep "mount สำหรับ chroot FAILED"
  fi
  ;;
4)
  srep "stage4: chroot sunny-init (sh -x) + sync ต่อเนื่อง"
  if mount -t ext4 -o rw,noatime "/dev/$UD" /mnt 2>/dev/null; then
    mkdir -p /mnt/proc /mnt/sys /mnt/dev
    mount --bind /proc /mnt/proc 2>/dev/null
    mount --bind /sys  /mnt/sys  2>/dev/null
    mount --bind /dev  /mnt/dev  2>/dev/null
    DOSYNC
    chroot /mnt /bin/sh -x /sbin/sunny-init >>/cache/sunny/sunnyx.log 2>&1 &
    srep "sunnyx started pid=$!"
    sleep 25
    srep "sunnyx tail: $(tail -n 15 /cache/sunny/sunnyx.log 2>/dev/null | tr '\n' '|')"
    cp /cache/sunny/sunnyx.log "$WWW/" 2>/dev/null
  else
    srep "mount สำหรับ stage4 FAILED"
  fi
  ;;
5)
  srep "stage5: sshd เท่านั้น (ไม่ mount/cgroup/net ใด ๆ)"
  if mount -t ext4 -o rw,noatime "/dev/$UD" /mnt 2>/dev/null; then
    mkdir -p /mnt/proc /mnt/sys /mnt/dev /mnt/run
    mount --bind /proc /mnt/proc 2>/dev/null
    mount --bind /sys  /mnt/sys  2>/dev/null
    mount --bind /dev  /mnt/dev  2>/dev/null
    mkdir -p /mnt/run/sshd; chmod 0755 /mnt/run/sshd
    R=$(chroot /mnt /usr/sbin/sshd -t 2>&1); srep "sshd -t: $R"
    R=$(chroot /mnt /usr/sbin/sshd -o PidFile=/run/sshd.pid 2>&1); srep "sshd start: $R"
    sleep 3
    srep "pid: $(cat /mnt/run/sshd.pid 2>/dev/null)"
  else
    srep "mount stage5 FAILED"
  fi
  ;;
*)
  srep "stage$STAGE: ไม่มีงาน — ค้าง serve"
  ;;
esac

srep "stage$STAGE: จบขั้น — dmesg ท้าย: $(dmesg 2>/dev/null | tail -n 3 | tr '\n' '|')"
sync

# ---------------- stage 0-3: reboot ไปขั้นถัดไป ----------------
if [ "$STAGE" -le 3 ]; then
  for f in /cache/sunny/stage*.log; do [ -f "$f" ] && cp "$f" "$WWW/" 2>/dev/null; done
  srep "reboot -> stage $((STAGE+1))"
  sync
  sleep 3
  reboot -f
fi

# ---------------- ค้างไว้เสิร์ฟต่อ ----------------
n=0
while true; do
  n=$((n+1))
  printf 'STAGE=%s alive up=%ss n=%s\n' "$STAGE" "$(cut -d. -f1 /proc/uptime)" "$n" >> "$LOG" 2>/dev/null
  sync 2>/dev/null
  printf 'STG hb%s up=%ss\n' "$n" "$(cut -d. -f1 /proc/uptime)"
  sleep 10
done
EOS
chmod +x "$IR/init"

cd "$IR"
find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$OUT/initramfs-staged.cpio.gz"
echo "==> $OUT/initramfs-staged.cpio.gz ($(( $(stat -c%s "$OUT/initramfs-staged.cpio.gz") / 1024 )) KB)"

MK="$SUNNY/tools/mkbootimg/mkbootimg.py"
[ -f "$OUT/dtb" ] || { echo "ต้องมี $OUT/dtb"; exit 1; }
CMDLINE="console=tty0 console=ttyMSM0,115200n8 console=ttyGS0,115200n8 \
androidboot.hardware=qcom androidboot.usbcontroller=a600000.dwc3 loop.max_part=7 \
lpm_levels.sleep_disabled=1 service_locator.enable=1 swiotlb=1 msm_rtb.filter=0x237 kpti=off"
python3 "$MK" --header_version 4 \
  --vendor_boot "$OUT/vendor_boot-staged.img" \
  --vendor_ramdisk "$OUT/initramfs-staged.cpio.gz" \
  --dtb "$OUT/dtb" \
  --vendor_cmdline "$CMDLINE" \
  --os_version 16.0.0 --os_patch_level 2026-05 --pagesize 4096

cp "$OUT/vendor_boot-staged.img" "/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out/vendor_boot-staged.img" 2>/dev/null || true
ls -lh "$OUT/vendor_boot-staged.img"
sha256sum "$OUT/vendor_boot-staged.img"
echo "เสร็จ: vendor_boot-staged.img"
