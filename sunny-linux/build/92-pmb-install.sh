#!/usr/bin/env bash
set -u
cd /root/sunny/src
rm -rf pmbootstrap
git clone --depth 1 -q https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git pmbootstrap 2>&1 | tail -3
cd pmbootstrap || exit 1
git log --oneline -1
echo "=== install deps ==="
python3 -m pip install --break-system-packages -q -e . 2>&1 | tail -5
echo "=== version ==="
python3 pmbootstrap.py --version 2>&1 | tail -3
echo "=== help (init) ==="
python3 pmbootstrap.py init --help 2>&1 | head -40
