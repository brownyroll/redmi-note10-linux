#!/usr/bin/env bash
set -u
P=/root/sunny/src/pmbootstrap
echo "=== vendor_boot support in pmbootstrap ==="
grep -rn "vendor_boot" "$P/pmb" 2>/dev/null | head -20
echo
echo "=== header_version / append_dtb refs ==="
grep -rn "header_version\|append_dtb" "$P/pmb" 2>/dev/null | head -15
echo
echo "=== config file path ==="
grep -rn "pmbootstrap.cfg\|PMB_CONFIG\|config.cfg" "$P/pmb/__init__.py" "$P/pmb/core/config"/*.py 2>/dev/null | head -15
echo
echo "=== how fastboot flash maps partitions ==="
grep -rn "def flash\|partition_boot\|flash_rootfs" "$P/pmb/flasher"/*.py 2>/dev/null | head -20
