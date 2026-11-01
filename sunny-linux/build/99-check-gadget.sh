#!/usr/bin/env bash
# 99-check-gadget.sh — ตรวจว่ามีอะไรตั้ง USB gadget (usb0 / ttyGS0) ใน rootfs ให้หรือยัง
set -uo pipefail
IMG="${1:-${SUNNY_ROOT:-/root/sunny}/out/rootfs.img}"
[ -f "$IMG" ] || { echo "ไม่พบ $IMG"; exit 1; }

echo "== ไฟล์/ยูนิตที่เกี่ยวกับ usb gadget =="
for f in /usr/local/sbin/usb-gadget.sh /usr/local/bin/usb-gadget.sh \
         /etc/systemd/system/usb-gadget.service \
         /lib/systemd/system/usb-gadget.service \
         /etc/systemd/system/multi-user.target.wants/usb-gadget.service \
         /etc/modules-load.d/sunny.conf \
         /etc/rc.local; do
  if debugfs -R "stat $f" "$IMG" 2>/dev/null | grep -q '^Inode:'; then echo "  ✓ $f"; else echo "  ✗ $f"; fi
done

echo
echo "== ค้นคำว่า configfs / g1 / rndis ใน /etc (เฉพาะ path ที่เจอ) =="
debugfs -R "rdump /etc /tmp/etc-scan" "$IMG" >/dev/null 2>&1
if [ -d /tmp/etc-scan ]; then
  grep -rlE 'configfs|/dev/g1|rndis|ttyGS0|usb_gadget' /tmp/etc-scan 2>/dev/null | sed 's|/tmp/etc-scan|/etc|' | head -20
  echo "  (ถ้าว่าง = ไม่มีใครตั้ง gadget เลย)"
  rm -rf /tmp/etc-scan
else
  echo "  แตก /etc ไม่ได้"
fi

echo
echo "== network config ที่มี =="
debugfs -R "ls -l /etc/systemd/network" "$IMG" 2>/dev/null | head
