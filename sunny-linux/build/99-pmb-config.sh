#!/usr/bin/env bash
# 99-pmb-config.sh — เขียน config pmbootstrap แบบไม่ต้อง interactive
set -u
mkdir -p /root/.local/var/pmbootstrap
CFG=/root/.config/pmbootstrap_v3.cfg
mkdir -p /root/.config

cat > "$CFG" <<'EOF'
[pmbootstrap]
aports = /root/sunny/src/pmaports
work = /root/.local/var/pmbootstrap
device = xiaomi-sunny-downstream
user = user
ui = console
hostname = sunny
locale = en_US.UTF-8
timezone = Asia/Bangkok
extra_packages = none
ssh_keys = true
jobs = 6
ccache_size = 2G
build_pkgs_on_install = false

[providers]
[mirrors]
EOF

chmod 600 "$CFG"
echo "=== config ==="
cat "$CFG"
echo
echo "=== required programs ==="
for p in git kpartx losetup openssl ps tar chroot sh; do
  if command -v "$p" >/dev/null 2>&1; then echo "ok   $p"; else echo "MISS $p"; fi
done
