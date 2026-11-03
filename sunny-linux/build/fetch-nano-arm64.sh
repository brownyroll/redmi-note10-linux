#!/usr/bin/env bash
# Cache and extract the real Ubuntu arm64 nano package for the native image.
set -euo pipefail
ROOT=${SUNNY_ROOT:-/root/sunny}
OUT="$ROOT/out"
DEB="$OUT/nano_arm64.deb"
PKG="$OUT/nano-pkg"
URL=https://ports.ubuntu.com/ubuntu-ports/pool/main/n/nano/nano_6.2-1ubuntu0.2_arm64.deb
if [ ! -x "$PKG/bin/nano" ]; then
  mkdir -p "$OUT"
  curl -fL "$URL" -o "$DEB.tmp"
  mv "$DEB.tmp" "$DEB"
  rm -rf "$PKG"; mkdir -p "$PKG"
  dpkg-deb -x "$DEB" "$PKG"
fi
[ "$(dpkg-deb -f "$DEB" Architecture)" = arm64 ]
file "$PKG/bin/nano" | grep -q 'ARM aarch64'
echo "nano: $(dpkg-deb -f "$DEB" Version) arm64"
