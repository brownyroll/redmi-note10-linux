#!/usr/bin/env bash
# 42-install-sunny-init.sh — ฝัง /sbin/sunny-init + ตั้ง sshd ลง rootfs.img แล้วสร้าง simg
#   bash 42-install-sunny-init.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUNNY="${SUNNY_ROOT:-/root/sunny}"
OUT="$SUNNY/out"
M="$SUNNY/mnt-root"
SRC="$HERE/sunny-init"
WIN="/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out"

[ -f "$SRC" ] || { echo "ไม่พบ $SRC"; exit 1; }
[ -f "$OUT/rootfs.img" ] || { echo "ไม่พบ $OUT/rootfs.img — รัน 37 ก่อน"; exit 1; }

mkdir -p "$M"
if mountpoint -q "$M"; then umount "$M" 2>/dev/null || umount -l "$M"; fi
mount -o loop,rw "$OUT/rootfs.img" "$M"
trap 'umount "$M" 2>/dev/null || true' EXIT

echo "==> ติดตั้ง /sbin/sunny-init"
sed 's/\r$//' "$SRC" > "$M/sbin/sunny-init.new"
chmod 0755 "$M/sbin/sunny-init.new"
mv "$M/sbin/sunny-init.new" "$M/sbin/sunny-init"
chown 0:0 "$M/sbin/sunny-init"
sh -n "$M/sbin/sunny-init" || { echo "✗ sunny-init มี syntax error"; exit 1; }
echo "    ok ($(wc -c < "$M/sbin/sunny-init") bytes)"

echo "==> เขียน sshd_config ให้ครบ (rootfs เดิมไม่มีไฟล์หลัก)"
SSHC="$M/etc/ssh/sshd_config"
SFTP="/usr/lib/openssh/sftp-server"
[ -x "$M$SFTP" ] || SFTP="/usr/lib/ssh/sftp-server"
mkdir -p "$M/etc/ssh/sshd_config.d"
# ไฟล์ override เดิม (ถ้ามี) ปิดไว้ เพื่อไม่ให้ทับค่าที่เราเขียน
for f in "$M"/etc/ssh/sshd_config.d/*.conf; do
  [ -f "$f" ] || continue
  echo "    ปิด override เดิม: ${f#$M} -> ${f#$M}.disabled"
  mv "$f" "$f.disabled"
done
cat > "$SSHC" <<EOF
# sshd_config — Ubuntu on Redmi Note 10 (sunny), เขียนโดย 42-install-sunny-init.sh
Port 22
AddressFamily any
ListenAddress 0.0.0.0
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
PidFile /run/sshd.pid
PermitRootLogin no
PasswordAuthentication yes
KbdInteractiveAuthentication no
UsePAM yes
PrintMotd yes
X11Forwarding no
AcceptEnv LANG LC_*
Subsystem sftp $SFTP
EOF
chmod 0644 "$SSHC"

echo "==> สร้าง user sshd (privilege separation) ถ้ายังไม่มี"
if ! grep -q '^sshd:' "$M/etc/passwd"; then
  UID_S=$(awk -F: 'BEGIN{u=106} {if($3>=100 && $3<=999 && $3==u) u=u+1} END{print u}' "$M/etc/passwd")
  grep -q '^sshd:' "$M/etc/group" || echo "sshd:x:$UID_S:" >> "$M/etc/group"
  echo "sshd:x:$UID_S:$UID_S:Privilege separation user:/run/sshd:/usr/sbin/nologin" >> "$M/etc/passwd"
  echo "sshd:!*:19000:0:99999:7:::" >> "$M/etc/shadow" 2>/dev/null || true
  echo "    + user sshd (uid=$UID_S)"
else
  echo "    มีอยู่แล้ว"
fi
[ -e "$M/var/run" ] || ln -s /run "$M/var/run"

echo "==> ตรวจ config ด้วย sshd -t (ผ่าน qemu-aarch64)"
cp /usr/bin/qemu-aarch64-static "$M/usr/bin/qemu-aarch64-static"
mkdir -p "$M/dev"
mount --bind /dev "$M/dev" 2>/dev/null
if chroot "$M" /usr/bin/qemu-aarch64-static /usr/sbin/sshd -t; then
  echo "    ✓ sshd_config ผ่าน"
else
  echo "    ✗ sshd_config ไม่ผ่าน (ดู error ข้างบน)"
fi
umount "$M/dev" 2>/dev/null || true
rm -f "$M/usr/bin/qemu-aarch64-static"

cat > "$M/etc/motd" <<'EOF'
Ubuntu 26.04 LTS — Redmi Note 10 4G (sunny)
  ssh dev@192.168.42.2   (รหัส: ubuntu1234)
  root shell บนจอ: autologin เป็น user dev
EOF

printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$M/etc/resolv.conf"

# ให้ /sbin/init ชี้ sunny-init ด้วย (เผื่อมีอะไรเรียก /sbin/init)
if [ ! -e "$M/sbin/init" ] || [ -L "$M/sbin/init" ]; then
  ln -sf /sbin/sunny-init "$M/sbin/init"
  echo "    /sbin/init -> /sbin/sunny-init"
fi

sync
umount "$M"
trap - EXIT
e2fsck -fy "$OUT/rootfs.img" >/dev/null 2>&1 || true

echo "==> สร้าง sparse image"
img2simg "$OUT/rootfs.img" "$OUT/rootfs.simg"
cp "$OUT/rootfs.simg" "$WIN/rootfs.simg" 2>/dev/null || true
ls -lh "$OUT/rootfs.img" "$OUT/rootfs.simg"
echo "เสร็จ: rootfs.simg พร้อมแฟลช (มี /sbin/sunny-init)"
