#!/data/data/com.termux/files/usr/bin/bash
# ---------------------------------------------------------------------------
# bootstrap-ubuntu.sh  —  Ubuntu Server (proot) on Redmi Note 10 4G "sunny"
#
#   วิธีใช้ (ใน Termux บนมือถือ):
#       termux-setup-storage
#       bash /sdcard/Download/bootstrap-ubuntu.sh
#
#   ตั้งค่าเพิ่มได้:
#       SSH_PORT=2222 UB_USER=dev UB_PASS=mysecret bash bootstrap-ubuntu.sh
#
#   ไม่ต้อง root / ไม่แตะ boot.img — ไม่เสี่ยง bootloop
# ---------------------------------------------------------------------------
set -uo pipefail

SSH_PORT="${SSH_PORT:-2222}"
UB_USER="${UB_USER:-dev}"
UB_PASS="${UB_PASS:-ubuntu1234}"
DISTRO="${DISTRO:-ubuntu}"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

[ -d /data/data/com.termux ] || { warn "ไม่ได้รันใน Termux"; exit 1; }

say "1/6  สภาพแวดล้อม"
echo "  arch: $(uname -m)   termux: $PREFIX"

say "2/6  ติดตั้ง proot-distro + openssh"
pkg update -y
pkg install -y proot-distro openssh termux-api || { warn "ติดตั้งแพ็กเกจไม่สำเร็จ"; exit 1; }

say "3/6  ขอ wake-lock (กัน Android ฆ่า process ตอนจอดับ)"
termux-wake-lock 2>/dev/null || warn "termux-wake-lock ใช้ไม่ได้ (ข้ามได้)"

say "4/6  ติดตั้ง Ubuntu ($DISTRO)"
if proot-distro list --installed 2>/dev/null | grep -qw "$DISTRO"; then
  echo "  มีอยู่แล้ว — ข้าม"
else
  proot-distro install "$DISTRO" || { warn "ติดตั้ง Ubuntu ไม่สำเร็จ (เช็คเน็ต/พื้นที่)"; exit 1; }
fi

say "5/6  ตั้งค่า user + sshd (port $SSH_PORT)"
mkdir -p "$TMPDIR"
cat > "$TMPDIR/ubuntu-setup.sh" <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y openssh-server sudo curl nano iproute2 procps less ca-certificates

id -u $UB_USER >/dev/null 2>&1 || adduser --disabled-password --gecos "" $UB_USER
echo "$UB_USER:$UB_PASS" | chpasswd
usermod -aG sudo $UB_USER
echo "$UB_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-$UB_USER
chmod 440 /etc/sudoers.d/90-$UB_USER

mkdir -p /run/sshd /var/run/sshd /etc/ssh/sshd_config.d
ssh-keygen -A

# drop-in นี้ถูก Include ก่อน config หลัก → ค่าที่ตั้งจะชนะ
cat > /etc/ssh/sshd_config.d/99-phone.conf <<'CONF'
Port PORT_PLACEHOLDER
PasswordAuthentication yes
PermitRootLogin no
UsePAM yes
CONF
sed -i "s/PORT_PLACEHOLDER/$SSH_PORT/" /etc/ssh/sshd_config.d/99-phone.conf
chmod 644 /etc/ssh/sshd_config.d/99-phone.conf

# กันค่าตรงข้ามใน config หลัก
sed -i -E 's/^[#[:space:]]*PasswordAuthentication[[:space:]].*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i -E 's/^[#[:space:]]*PermitRootLogin[[:space:]].*/PermitRootLogin no/' /etc/ssh/sshd_config

echo "Ubuntu server on Redmi Note 10 4G (sunny) — ssh port $SSH_PORT" > /etc/motd
/usr/sbin/sshd -t && echo "sshd config OK (port $SSH_PORT)"
EOS

proot-distro login "$DISTRO" --shared-tmp -- bash /tmp/ubuntu-setup.sh

say "6/6  เพิ่มคำสั่งช่วยใช้"
cat > "$HOME/start-ubuntu" <<EOS
#!/data/data/com.termux/files/usr/bin/bash
# เปิด Ubuntu + sshd (port $SSH_PORT)
termux-wake-lock 2>/dev/null
pkill -f 'sshd.*-D' 2>/dev/null
sleep 1
nohup proot-distro login $DISTRO -- /usr/sbin/sshd -D -e -p $SSH_PORT > "\$HOME/ubuntu-sshd.log" 2>&1 &
sleep 4
echo "-- IP เครื่องนี้ --"
ip -4 addr 2>/dev/null | awk '/^[0-9]+: (wlan0|tailscale0)/{iface=\$2} /inet /{if(iface!=""){print "  " iface, \$2}}'
echo "-- log sshd --"
tail -n 5 "\$HOME/ubuntu-sshd.log" 2>/dev/null || echo "  (ยังไม่มี log)"
echo
echo "  ssh $UB_USER@<ip ข้างบน> -p $SSH_PORT"
EOS
chmod +x "$HOME/start-ubuntu"

cat > "$HOME/stop-ubuntu" <<'EOS'
#!/data/data/com.termux/files/usr/bin/bash
pkill -f 'sshd.*-D' 2>/dev/null && echo "sshd stopped" || echo "sshd ไม่ได้รันอยู่"
termux-wake-unlock 2>/dev/null
EOS
chmod +x "$HOME/stop-ubuntu"

cat > "$HOME/ubuntu-shell" <<EOS
#!/data/data/com.termux/files/usr/bin/bash
exec proot-distro login $DISTRO -- /bin/bash -l
EOS
chmod +x "$HOME/ubuntu-shell"

# auto-start ตอนบูตเครื่อง (ต้องติดตั้ง Termux:Boot ด้วย)
mkdir -p "$HOME/.termux/boot"
cat > "$HOME/.termux/boot/10-start-ubuntu.sh" <<EOS
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
sleep 10
nohup proot-distro login $DISTRO -- /usr/sbin/sshd -D -e -p $SSH_PORT > "\$HOME/ubuntu-sshd.log" 2>&1 &
EOS
chmod +x "$HOME/.termux/boot/10-start-ubuntu.sh"

say "เสร็จแล้ว"
cat <<EOS

  ~/start-ubuntu     เปิด Ubuntu + sshd
  ~/stop-ubuntu      ปิด
  ~/ubuntu-shell     เข้า Ubuntu (ใน Termux)
  ~/ubuntu-sshd.log  log

  user: $UB_USER    password: $UB_PASS    port: $SSH_PORT
  เปลี่ยนรหัส: proot-distro login $DISTRO -- passwd $UB_USER
EOS
