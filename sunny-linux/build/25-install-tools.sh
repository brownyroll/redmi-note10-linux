#!/usr/bin/env bash
# 25-install-tools.sh — ติดตั้งเครื่องมือ payload/avb ใน WSL
set -euo pipefail
python3 -m pip install --break-system-packages --quiet payload-dumper zstandard brotli 2>&1 | tail -5 || true
# ให้ชื่อทั่วไปตรวจได้
python3 - <<'PY'
ok = []
try:
    import payload_dumper; ok.append("payload_dumper")
except ImportError: pass
try:
    import zstandard; ok.append("zstandard")
except ImportError: pass
try:
    import brotli; ok.append("brotli")
except ImportError: pass
print("python modules:", ok)
assert "payload_dumper" in ok, "ติดตั้ง payload_dumper ไม่สำเร็จ"
assert "zstandard" in ok, "ต้องมี zstandard (payload Android 15+ ใช้ zstd)"
print("OK")
PY
