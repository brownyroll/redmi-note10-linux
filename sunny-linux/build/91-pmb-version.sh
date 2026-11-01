#!/usr/bin/env bash
set -u
P=/root/sunny/src/pmbootstrap
echo "=== pyproject deps ==="
sed -n '1,60p' "$P/pyproject.toml"
echo "=== try run ==="
cd "$P" && python3 pmbootstrap.py --version 2>&1 | tail -5
