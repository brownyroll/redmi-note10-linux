#!/usr/bin/env bash
# B1-fix-pmaports-remote.sh — ชี้ remote ไป gitlab.postmarketos.org + ให้มี origin/main/channels.cfg
set -u
cd /root/sunny/src/pmaports || exit 1
git remote set-url origin https://gitlab.postmarketos.org/postmarketOS/pmaports.git
git fetch --depth=1 origin main 2>&1 | tail -3
git branch -M main 2>/dev/null
git update-ref refs/remotes/origin/main refs/heads/main 2>/dev/null || true
echo "--- channels.cfg present? ---"
ls -l channels.cfg 2>&1
echo "--- origin/main ---"
git rev-parse --short origin/main 2>&1
git show origin/main:channels.cfg 2>&1 | head -10
