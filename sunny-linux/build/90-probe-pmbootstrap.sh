#!/usr/bin/env bash
ls -a /root/sunny/src/pmbootstrap 2>/dev/null | head -20
echo "--- ls-remote tests ---"
for u in https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git \
         https://codeberg.org/postmarketOS/pmbootstrap.git \
         https://github.com/postmarketOS/pmbootstrap.git ; do
  echo "== $u"
  git ls-remote --heads "$u" 2>&1 | head -3
done
