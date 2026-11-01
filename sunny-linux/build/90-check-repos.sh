#!/usr/bin/env bash
# 90-check-repos.sh — เช็ค repo บน GitHub ที่เกี่ยวกับ sunny/mojito (ไม่ต้องใช้ gh cli)
set -u
for r in yaap/device_xiaomi_sunny-kernel xdroid-devices/xd_device_xiaomi_sunny Neternels/android_kernel_xiaomi_sunny MiCode/Xiaomi_Kernel_OpenSource xiaomi-sm6150-dev/android_device_xiaomi_sm6150-common; do
  echo "=== $r ==="
  curl -s "https://api.github.com/repos/$r" | python3 -c 'import sys,json
d=json.load(sys.stdin)
if "full_name" not in d:
    print("  ->", d.get("message")); raise SystemExit
print("  default:", d.get("default_branch"), "| size(KB):", d.get("size"), "| archived:", d.get("archived"), "| pushed:", d.get("pushed_at"))'
  curl -s "https://api.github.com/repos/$r/contents/" | python3 -c 'import sys,json
d=json.load(sys.stdin)
if isinstance(d,list):
    print("  files:", " ".join(x["name"] for x in d[:30]))
else:
    print("  ->", d.get("message"))'
done
echo
echo "=== branches: Neternels/android_kernel_xiaomi_sunny ==="
curl -s "https://api.github.com/repos/Neternels/android_kernel_xiaomi_sunny/branches?per_page=100" | python3 -c 'import sys,json
d=json.load(sys.stdin)
print("  ", " ".join(b["name"] for b in d) if isinstance(d,list) else d)'

echo
echo "=== branches: yaap/device_xiaomi_sunny-kernel ==="
curl -s "https://api.github.com/repos/yaap/device_xiaomi_sunny-kernel/branches?per_page=100" | python3 -c 'import sys,json
d=json.load(sys.stdin)
print("  ", " ".join(b["name"] for b in d) if isinstance(d,list) else d)'
