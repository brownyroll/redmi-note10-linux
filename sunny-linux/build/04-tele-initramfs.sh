#!/usr/bin/env bash
# 04-tele-initramfs.sh — initramfs ที่ "พูดซ้ำ ๆ ทาง COM10" (ticker) จนกว่าโฮสต์จะได้ยิน
#   เหตุผล: USB ACM ใช้เวลาราว 10-20 วิกว่าจะ enumerate → ข้อความที่พิมพ์ตอนต้นหายหมด
#   แก้: เก็บ LOG ใน RAM แล้วพิมพ์ซ้ำทุก 3 วิ (ท้าย 45 บรรทัด + dmesg 3 บรรทัด)
#   + mount devpts ให้ telnetd ใช้งานได้จริง + stage counter บน cache (ทดลองต่อเนื่องข้ามรีบูต)
#   ผลลัพธ์: out/vendor_boot-tele.img
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
SUNNY="${SUNNY_ROOT:-/root/sunny}"
[ -d "$SUNNY/out" ] || SUNNY="$ROOT"
OUT="$SUNNY/out"
IR="$OUT/initramfs-tele"
BB="${BUSYBOX_AARCH64:-$OUT/busybox-aarch64}"
[ -f "$BB" ] || { echo "ต้องมี $BB"; exit 1; }
rm -rf "$IR"; mkdir -p "$IR/bin" "$IR/dev" "$IR/dev/pts" "$IR/proc" "$IR/sys" "$IR/mnt" "$IR/cache"
cp "$BB" "$IR/bin/busybox"; chmod +x "$IR/bin/busybox"
file "$IR/bin/busybox" | grep -q 'ARM aarch64' || { echo "busybox ไม่ใช่ aarch64"; exit 1; }

cat > "$IR/init" <<'EOS'
#!/bin/busybox sh
/bin/busybox --install -s /bin
export PATH=/bin:/sbin
mount -t proc  proc  /proc
mount -t sysfs sys   /sys
mount -t devtmpfs dev /dev
mkdir -p /dev/pts /dev/shm
mount -t devpts devpts /dev/pts 2>/dev/null

LOG=/log.txt
: > "$LOG"
say() { printf '%s\n' "$*" >> "$LOG"; printf 'TL %s\n' "$*" > /dev/ttyGS0 2>/dev/null; return 0; }

# ---------------- USB gadget ----------------
mkdir /configfs 2>/dev/null
mount -t configfs none /configfs 2>/dev/null
G=/configfs/usb_gadget/g1
mkdir -p "$G" "$G/strings/0x409" "$G/configs/c.1/strings/0x409" \
         "$G/functions/rndis.usb0" "$G/functions/acm.GS1" 2>/dev/null
echo 0x1d6b > "$G/idVendor";  echo 0x0104 > "$G/idProduct"
echo 0x0100 > "$G/bcdDevice"; echo 0x0200 > "$G/bcdUSB"
echo "579a9d18"   > "$G/strings/0x409/serialnumber"
echo "sunny-tele" > "$G/strings/0x409/manufacturer"
echo "sunny tele" > "$G/strings/0x409/product"
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
    say "net=$IF ok"
  fi
  telnetd -l /bin/sh -p 23 2>/dev/null &
  say "telnetd 23 started"
fi

# ---------------- watchdog ----------------
for wd in /dev/watchdog /dev/watchdog0 /dev/watchdog1; do
  if [ -e "$wd" ]; then
    ( while :; do printf '1' > "$wd" 2>/dev/null; sleep 5; done ) &
    say "watchdog $wd fed"
    break
  fi
done

# ---------------- ticker: พิมพ์ log ซ้ำจนโฮสต์ได้ยิน ----------------
( while :; do
    tail -n 45 "$LOG" 2>/dev/null
    printf 'NT dmesg: %s\n' "$(dmesg 2>/dev/null | tail -n 2 | tr '\n' '|')"
    printf 'NT ---- up=%ss ----\n' "$(cut -d. -f1 /proc/uptime)"
    sleep 3
  done > /dev/ttyGS0 2>/dev/null ) &
say "ticker started"

# ---------------- partitions ----------------
mdev -s 2>/dev/null
find_part() {
  for u in /sys/class/block/*/uevent; do
    [ -f "$u" ] || continue
    if grep -q "^PARTNAME=$1$" "$u" 2>/dev/null; then basename "$(dirname "$u")"; return 0; fi
  done
  return 1
}
i=0
while [ $i -lt 20 ]; do
  UD=$(find_part userdata); [ -n "${UD:-}" ] && break
  mdev -s 2>/dev/null; sleep 1; i=$((i+1))
done
CA=$(find_part cache)
say "parts ud=${UD:-none} ca=${CA:-none}"

STAGE=0
if [ -n "${CA:-}" ] && mount -t ext4 -o rw,noatime "/dev/$CA" /cache 2>/dev/null; then
  mkdir -p /cache/sunny 2>/dev/null
  [ -f /cache/sunny/stage ] && STAGE=$(cat /cache/sunny/stage 2>/dev/null)
  case "${STAGE:-x}" in ''|*[!0-9]*) STAGE=0 ;; esac
  printf '%s' "$((STAGE+1))" > /cache/sunny/stage 2>/dev/null
  sync
  say "cache ok, STAGE=$STAGE (next=$((STAGE+1)))"
  cp /cache/sunny/*.log /tmp/ 2>/dev/null
else
  say "cache unavailable — STAGE=$STAGE (จะวน stage 0)"
fi

say "cmdline: $(cat /proc/cmdline)"
say "panic=$(cat /proc/sys/kernel/panic 2>/dev/null) pstore=$(ls /sys/fs/pstore 2>/dev/null | tr '\n' ' ')"
for f in /sys/fs/pstore/*; do
  [ -f "$f" ] || continue
  say "--- pstore $(basename "$f") $(wc -c < "$f")B ---"
  tail -n 120 "$f" 2>/dev/null | while IFS= read -r l; do printf 'KB %s\n' "$l" >> "$LOG"; done
done
say "--- dmesg tail ---"
dmesg 2>/dev/null | tail -n 30 | while IFS= read -r l; do printf 'DM %s\n' "$l" >> "$LOG"; done
[ -f /cache/sunny/prev.log ] && { say "--- prev stage log ---"; tail -n 40 /cache/sunny/prev.log | while IFS= read -r l; do printf 'PV %s\n' "$l" >> "$LOG"; done; }

# ---------------- stage ทำงาน ----------------
case "$STAGE" in
0) say "stage0: baseline (ไม่แตะ userdata)" ;;
1)
  say "stage1: userdata RO"
  if mount -t ext4 -o ro "/dev/$UD" /mnt 2>/dev/null; then
    say "RO OK: $(ls /mnt | tr '\n' ' ' | cut -c1-200)"
    say "os: $(head -2 /mnt/etc/os-release 2>/dev/null | tr '\n' ' ')"
    umount /mnt 2>/dev/null; say "umount ro done"
  else say "RO FAILED"; fi ;;
2)
  say "stage2: userdata RW + write"
  if mount -t ext4 -o rw,noatime "/dev/$UD" /mnt 2>/dev/null; then
    say "RW mount OK"
    echo "rwtest" > /mnt/rwtest.txt; say "write rc=$?"; sync; say "sync done"
    umount /mnt 2>/dev/null; say "umount rw rc=$?"
  else say "RW FAILED"; fi ;;
3)
  say "stage3: chroot shell"
  if mount -t ext4 -o rw,noatime "/dev/$UD" /mnt 2>/dev/null; then
    mkdir -p /mnt/proc /mnt/sys /mnt/dev
    mount --bind /proc /mnt/proc 2>/dev/null; mount --bind /sys /mnt/sys 2>/dev/null; mount --bind /dev /mnt/dev 2>/dev/null
    R=$(chroot /mnt /bin/sh -c 'echo CHROOT_OK; id -u; head -1 /etc/os-release' 2>&1)
    say "chroot rc=$? out=$(printf '%s' "$R" | tr '\n' '/')"
  else say "mount for chroot FAILED"; fi ;;
4)
  say "stage4: chroot sunny-init (sh -x)"
  if mount -t ext4 -o rw,noatime "/dev/$UD" /mnt 2>/dev/null; then
    mkdir -p /mnt/proc /mnt/sys /mnt/dev
    mount --bind /proc /mnt/proc 2>/dev/null; mount --bind /sys /mnt/sys 2>/dev/null; mount --bind /dev /mnt/dev 2>/dev/null
    ( while :; do sync 2>/dev/null; sleep 2; done ) &
    chroot /mnt /bin/sh -x /sbin/sunny-init >/cache/sunny/sunnyx.log 2>&1 &
    say "sunnyx pid=$!"
    sleep 20
    say "sunnyx: $(tail -n 12 /cache/sunny/sunnyx.log 2>/dev/null | tr '\n' '|')"
  else say "mount stage4 FAILED"; fi ;;
5) say "stage5: sshd only (no mounts/cgroup/net)" ;;
*) say "stage$STAGE: none" ;;
esac

say "stage$STAGE DONE"
[ -f /cache/sunny/stage$STAGE.log ] || cp "$LOG" /cache/sunny/stage$STAGE.log 2>/dev/null
cp "$LOG" /cache/sunny/prev.log 2>/dev/null
sync

if [ "$STAGE" -le 3 ]; then
  say "rebooting -> stage $((STAGE+1))"
  sync; sleep 4; reboot -f
fi

while :; do sleep 10; done
EOS
chmod +x "$IR/init"

cd "$IR"
find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$OUT/initramfs-tele.cpio.gz"
echo "==> $OUT/initramfs-tele.cpio.gz ($(( $(stat -c%s "$OUT/initramfs-tele.cpio.gz") / 1024 )) KB)"

MK="$SUNNY/tools/mkbootimg/mkbootimg.py"
[ -f "$OUT/dtb" ] || { echo "ต้องมี $OUT/dtb"; exit 1; }
CMDLINE="console=tty0 console=ttyMSM0,115200n8 console=ttyGS0,115200n8 \
androidboot.hardware=qcom androidboot.usbcontroller=a600000.dwc3 loop.max_part=7 \
lpm_levels.sleep_disabled=1 service_locator.enable=1 swiotlb=1 msm_rtb.filter=0x237 kpti=off"
python3 "$MK" --header_version 4 \
  --vendor_boot "$OUT/vendor_boot-tele.img" \
  --vendor_ramdisk "$OUT/initramfs-tele.cpio.gz" \
  --dtb "$OUT/dtb" \
  --vendor_cmdline "$CMDLINE" \
  --os_version 16.0.0 --os_patch_level 2026-05 --pagesize 4096

cp "$OUT/vendor_boot-tele.img" "/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out/vendor_boot-tele.img" 2>/dev/null || true
ls -lh "$OUT/vendor_boot-tele.img"; sha256sum "$OUT/vendor_boot-tele.img"
echo "เสร็จ: vendor_boot-tele.img"
