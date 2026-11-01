#!/usr/bin/env bash
# 06-flash.sh — แฟลชขึ้นเครื่อง sunny (A/B, AVB เปิด)
#   bash 06-flash.sh boot        # boot + vendor_boot + vbmeta
#   bash 06-flash.sh userdata    # rootfs.img → userdata (ผ่าน TWRP, dd + .gz)
#   bash 06-flash.sh userdata-sparse   # rootfs.img → userdata (fastboot sparse, ไม่ต้อง TWRP)
#   bash 06-flash.sh stock       # คืนค่า boot stock ที่สำรองไว้
#
#   ต้องมี fastboot/adb ใน PATH และอยู่โฟลเดอร์ build/
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
OUT="$ROOT/out"
MODE="${1:-boot}"
TWRP="${TWRP:-$ROOT/twrp-sunny.img}"

confirm() {
  echo; echo "⚠️  $1"; read -r -p "พิมพ์ 'yes' เพื่อไปต่อ: " a
  [ "$a" = yes ] || { echo "ยกเลิก"; exit 1; }
}

need_fastboot() {
  fastboot devices | grep -q . || { echo "ไม่พบเครื่องใน fastboot (adb ใช้ไม่ได้ในโหมดนี้)"; exit 2; }
}

case "$MODE" in
boot)
  need_fastboot
  [ -f "$OUT/boot.img" ] && [ -f "$OUT/vendor_boot.img" ] || { echo "ยังไม่มี boot/vendor_boot — รัน 05-bootimg.sh"; exit 1; }
  echo "==> ปิด AVB verification (vbmeta flags=2)"
  if command -v avbtool >/dev/null 2>&1; then
    avbtool make_vbmeta_image --flags 2 --output "$OUT/vbmeta.img"
  elif python3 -c 'import avbtool' 2>/dev/null; then
    python3 -c "from avbtool import Avb; Avb().make_vbmeta_image(['--flags','2','--output','$OUT/vbmeta.img'])"
  else
    echo "  ไม่มี avbtool — ข้ามการแตะ vbmeta (ถ้าไม่บูตให้ติดตั้ง: pip install avbtool)"; VBMETA=""
  fi
  confirm "จะเขียน boot + vendor_boot (ของเดิมสำรองไว้แล้วใช่ไหม?)"
  fastboot flash boot "$OUT/boot.img"
  fastboot flash vendor_boot "$OUT/vendor_boot.img"
  [ -f "$OUT/vbmeta.img" ] && fastboot --disable-verity --disable-verification flash vbmeta "$OUT/vbmeta.img" || true
  echo "==> reboot"; fastboot reboot
  ;;

userdata)
  echo "==> เขียน rootfs ลง userdata ผ่าน TWRP"
  SRCIMG="$OUT/rootfs.img"
  SRCGZ="$OUT/rootfs.img.gz"
  [ -f "$SRCIMG" ] || [ -f "$SRCGZ" ] || { echo "ยังไม่มี rootfs.img — รัน 03-rootfs.sh"; exit 1; }
  [ -f "$TWRP" ] || { echo "ไม่พบ TWRP: $TWRP (ตั้ง TWRP=/path/twrp.img)"; exit 1; }
  need_fastboot
  confirm "userdata ทั้งหมดจะถูกเขียนทับ (รูป/ข้อมูลหายหมด)"
  fastboot boot "$TWRP"
  for i in $(seq 1 40); do sleep 3; adb shell echo ok 2>/dev/null | grep -q ok && break; done

  if [ -f "$SRCGZ" ]; then
    echo "  ใช้ไฟล์บีบอัด: $(du -h "$SRCGZ" | cut -f1)"
    adb push "$SRCGZ" /sdcard/rootfs.img.gz
    adb shell "gzip -dc /sdcard/rootfs.img.gz | dd of=/dev/block/by-name/userdata bs=4M"
    adb shell "rm -f /sdcard/rootfs.img.gz"
  else
    echo "  ใช้ไฟล์ดิบ: $(du -h "$SRCIMG" | cut -f1)"
    adb push "$SRCIMG" /sdcard/rootfs.img
    adb shell "dd if=/sdcard/rootfs.img of=/dev/block/by-name/userdata bs=4M"
    adb shell "rm -f /sdcard/rootfs.img"
  fi

  echo "==> ขยาย fs ให้เต็มพาร์ทิชัน (~105 GB) + fsck"
  adb shell "e2fsck -fy /dev/block/by-name/userdata || true; resize2fs /dev/block/by-name/userdata || true"
  adb shell "sync"
  echo "==> reboot"; adb reboot
  ;;

userdata-sparse)
  # ทางเลือกที่ไม่ต้องใช้ TWRP: แปลงเป็น sparse แล้วให้ fastboot แบ่งก้อนเอง
  need_fastboot
  [ -f "$OUT/rootfs.img" ] || { echo "ยังไม่มี rootfs.img — รัน 03-rootfs.sh"; exit 1; }
  command -v img2simg >/dev/null 2>&1 || { echo "ต้องมี img2simg (apt install android-sdk-libsparse-utils)"; exit 1; }
  confirm "userdata ทั้งหมดจะถูกเขียนทับด้วย rootfs (ข้อมูลหายหมด)"
  echo "==> แปลงเป็น sparse"
  img2simg "$OUT/rootfs.img" "$OUT/rootfs.simg"
  ls -lh "$OUT/rootfs.simg"
  echo "==> แฟลช (แบ่งก้อนละ 400 MB ตาม max-download-size)"
  fastboot flash -S 400M userdata "$OUT/rootfs.simg"
  echo "==> reboot"; fastboot reboot
  ;;

stock)
  need_fastboot
  B=$(ls -1 "$ROOT"/logs/backup_*/boot_a.img 2>/dev/null | head -1 || true)
  V=$(ls -1 "$ROOT"/logs/backup_*/vendor_boot_a.img 2>/dev/null | head -1 || true)
  [ -n "$B" ] || { echo "ไม่พบ boot_a.img ที่สำรองไว้"; exit 1; }
  confirm "จะเขียน boot กลับเป็นของเดิม ($B)"
  fastboot flash boot "$B"
  [ -n "$V" ] && fastboot flash vendor_boot "$V"
  fastboot reboot
  ;;
*) echo "ใช้: bash 06-flash.sh [boot|userdata|userdata-sparse|stock]"; exit 1 ;;
esac
