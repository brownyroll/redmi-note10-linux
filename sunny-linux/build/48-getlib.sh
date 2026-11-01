#!/usr/bin/env bash
# 48-getlib.sh — ดาวน์โหลด .deb ของ arm64 จาก ports.ubuntu.com แล้วแตกใส่ rootfs image
#   usage: 48-getlib.sh libwrap0 [pkg2 ...]
set -u
SUNNY="${SUNNY_ROOT:-/root/sunny}"
M="$SUNNY/mnt-root"
WORK="$SUNNY/tmp/debs"
mkdir -p "$WORK" "$M"
mountpoint -q "$M" || mount -o loop,rw "$SUNNY/out/rootfs.img" "$M" || exit 1

find_deb() {
  local pkg="$1" suite fn
  for suite in resolute noble jammy; do
    for comp in main universe; do
      url="http://ports.ubuntu.com/ubuntu-ports/dists/$suite/$comp/binary-arm64/Packages.gz"
      fn=$(curl -s --max-time 30 "$url" | gzip -dc 2>/dev/null | \
           awk -v p="$pkg" 'BEGIN{RS="";FS="\n"} {name="";file=""} {for(i=1;i<=NF;i++){if($i ~ "^Package: "p"$")name=p; if($i ~ "^Filename: ")file=substr($i,11)}} name==p && file!="" {print file; exit}')
      if [ -n "$fn" ]; then
        echo "http://ports.ubuntu.com/ubuntu-ports/$fn"
        return
      fi
    done
  done
}

for pkg in "$@"; do
  echo "== $pkg"
  u=$(find_deb "$pkg")
  if [ -z "$u" ]; then echo "   ✗ หา .deb ไม่เจอ"; continue; fi
  f="$WORK/$(basename "$u")"
  curl -sL --max-time 120 -o "$f" "$u" || { echo "   ✗ ดาวน์โหลดไม่สำเร็จ"; continue; }
  echo "   $(basename "$u")"
  dpkg -x "$f" "$M"
  echo "   ✓ แตกแล้ว"
done
sync
echo "เสร็จ"
