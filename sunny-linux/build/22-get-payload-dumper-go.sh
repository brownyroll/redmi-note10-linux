#!/usr/bin/env bash
# 22-get-payload-dumper-go.sh — ดาวน์โหลด payload-dumper-go สำหรับ linux/amd64 (WSL)
#   bash 22-get-payload-dumper-go.sh
set -euo pipefail
ROOT="${SUNNY_ROOT:-/root/sunny}"
DIR="$ROOT/tools/payload-dumper-go"
[ -x "$DIR/payload-dumper-go" ] && { echo "มีอยู่แล้ว"; exit 0; }
mkdir -p "$DIR"
# จะกำหนด tag ที่นี่และแจกมาจาก releases ของ JonasZY หรือ ssismm
URL="${PDG_URL:-https://github.com/ssut/payload-dumper-go/releases/download/2.1.0/payload-dumper-go_2.1.0_linux_amd64.tar.gz}"

retry() { for i in 1 2 3; do curl -L --no-progress-meter -o "$DIR/pdg.tar.gz" "$1" && return 0; sleep 2; done; return 1; }
set +e
retry "$URL" ||
retry "https://github.com/ssut/payload-dumper-go/releases/download/2.1.0/payload-dumper-go_2.1.0_linux_amd64_avx2.tar.gz"
set -e
[ -s "$DIR/pdg.tar.gz" ] || { echo "โหลดไม่ได้ — ให้หา URL ใหม่"; exit 1; }
tar -xzf "$DIR/pdg.tar.gz" -C "$DIR"
ls -lh "$DIR"
"$DIR/payload-dumper-go" --help 2>&1 | head -10 || true
