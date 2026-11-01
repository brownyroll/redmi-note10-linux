#!/usr/bin/env bash
# 99-wsl-probe.sh — ตรวจความพร้อมของ WSL ก่อน build (รันจากฝั่ง Windows: wsl bash <ไฟล์นี้>)
echo "== os =="
. /etc/os-release 2>/dev/null && echo "  $PRETTY_NAME"
echo "  kernel: $(uname -r)"
echo "  nproc : $(nproc)"
echo "  ram   : $(free -g | awk '/^Mem:/{print $2" GB total, "$7" GB avail"}')"
echo "  disk  : $(df -h / | awk 'NR==2{print $4" free of "$2}')"
echo "  c:    : $(df -h /mnt/c 2>/dev/null | awk 'NR==2{print $4" free"}')"

echo "== sudo =="
if sudo -n true 2>/dev/null; then echo "  NOPASSWD ok"; else echo "  ต้องใส่รหัส (จะข้ามการติดตั้งแพ็กเกจ)"; fi

echo "== tools =="
for t in aarch64-linux-gnu-gcc dtc mkbootimg cpio mke2fs python3 git curl bison flex cc; do
  printf '  %-24s %s\n' "$t" "$(command -v "$t" || echo 'MISSING')"
done
