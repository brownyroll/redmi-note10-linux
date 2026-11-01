#!/usr/bin/env bash
# A2-pmb-check-device.sh — ตรวจว่า pmbootstrap มองเห็น device ของเรา + deviceinfo ถูกต้อง
set -u
cd /root/sunny/src/pmbootstrap || exit 1
echo "=== device list (grep sunny) ==="
python3 pmbootstrap.py --as-root config device 2>&1 | head -5
echo
echo "=== pmaports info ==="
python3 - <<'PY'
import sys
sys.path.insert(0, "/root/sunny/src/pmbootstrap")
from pmb.core.context import get_context, set_context
from pmb.core.context import Context
PY
echo
echo "=== deviceinfo parse ==="
python3 - <<'PY'
import sys
sys.path.insert(0, "/root/sunny/src/pmbootstrap")
from pmb.parse.deviceinfo import deviceinfo
try:
    d = deviceinfo("xiaomi-sunny-downstream")
    for k in ("codename","name","arch","flash_method","header_version","generate_bootimg",
              "kernel_cmdline","screen_width","screen_height","dtb","flash_pagesize"):
        print(f"{k:20} = {getattr(d, k, None)}")
except Exception as e:
    print("ERROR:", type(e).__name__, e)
PY
