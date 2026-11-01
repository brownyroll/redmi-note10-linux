#!/usr/bin/env bash
# 02-kernel.sh — cross-compile Image + dtbs + modules
#   bash 02-kernel.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${SUNNY_ROOT:-$HERE/..}"
K="$ROOT/src/kernel"
OUT="$ROOT/out"
export ARCH=arm64 SUBARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
export KBUILD_BUILD_USER=sunny KBUILD_BUILD_HOST=sunny-linux
# GCC 13 เข้มกว่า toolchain ปี 2020 ที่ kernel 4.14 ถูกเขียนมา → ปิด -Werror
export KCFLAGS="-Wno-error -Wno-array-bounds -Wno-stringop-overflow -Wno-dangling-pointer -Wno-use-after-free -Wno-format-overflow"
mkdir -p "$OUT"

[ -d "$K" ] || { echo "ยังไม่มี kernel — รัน 01-sources.sh ก่อน"; exit 1; }
cd "$K"

# ---- หา defconfig ----
DEFCONFIG=""
for c in vendor/sunny_defconfig sunny_defconfig vendor/sunny-perf_defconfig vendor/mojito_defconfig; do
  [ -f "arch/arm64/configs/$c" ] && { DEFCONFIG="$c"; break; }
done
if [ -z "$DEFCONFIG" ]; then
  DEFCONFIG=$(ls arch/arm64/configs 2>/dev/null | grep -iE 'sunny|mojito' | head -1)
fi
[ -n "$DEFCONFIG" ] || { echo "หา defconfig ของ sunny ไม่เจอ — ดูใน arch/arm64/configs"; ls arch/arm64/configs | head; exit 1; }
echo "==> defconfig: $DEFCONFIG"

make O="$OUT" "$DEFCONFIG"
scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" "$HERE/sunny.fragment"
# olddefconfig = ไม่ถาม, เติม default ให้ symbol ที่ยังว่าง
make O="$OUT" olddefconfig >/dev/null
make O="$OUT" olddefconfig >/dev/null
# ต้องมีค่าจริง ไม่งั้น make จะไปค้างที่ silentoldconfig
if grep -qE '^CONFIG_LITTLE_CPU_MASK=$' "$OUT/.config"; then
  echo "✗ LITTLE_CPU_MASK ยังว่าง — แก้ sunny.fragment ก่อน"; exit 1
fi
grep -E '^(CONFIG_(LITTLE|BIG)_CPU_MASK|CONFIG_NR_CPUS)=' "$OUT/.config"

# ---- build ----
echo "==> build -j$(nproc)"
make O="$OUT" -j"$(nproc)" Image dtbs modules 2>&1 | tee "$OUT/build.log" | tail -20

echo "==> modules_install (ถ้ามี .ko)"
make O="$OUT" INSTALL_MOD_PATH="$OUT/modules" -j"$(nproc)" modules_install >/dev/null 2>&1 \
  && echo "  ok" || echo "  (ไม่มี module ให้ติดตั้ง — ข้าม)"

# ---- รวบรวมผล ----
cp "$OUT/arch/arm64/boot/Image" "$OUT/Image"
DTBS=$(ls "$OUT"/arch/arm64/boot/dts/qcom/*.dtb 2>/dev/null)
if [ -f "$OUT/arch/arm64/boot/dts/qcom/sm6150.dtb" ]; then
  cp "$OUT/arch/arm64/boot/dts/qcom/sm6150.dtb" "$OUT/dtb"
  echo "==> dtb: ใช้ sm6150.dtb ที่ build จากซอร์ส ($(stat -c%s "$OUT/dtb") bytes)"
elif [ -n "$DTBS" ]; then
  echo "==> มี dtb อื่น: $(echo "$DTBS" | xargs -n1 basename | tr '\n' ' ')"
else
  echo "==> ไม่มี dtb ที่ build ได้ — ใช้ prebuilt ที่มีอยู่ ($OUT/dtb)"
fi
{
  echo "kernel: $(grep -m1 '^VERSION' Makefile) $(make O="$OUT" kernelrelease 2>/dev/null)"
  echo "image : $(stat -c%s "$OUT/Image" 2>/dev/null) bytes"
  echo "dtb   : $(stat -c%s "$OUT/dtb" 2>/dev/null) bytes"
  echo "config: $(stat -c%s "$OUT/.config") bytes"
} | tee "$OUT/summary.txt"

echo
echo "ผลลัพธ์:"
echo "  $OUT/Image       ← kernel"
echo "  $OUT/dtb         ← รวม dtb (ตรวจว่ามี sunny/mojito อยู่จริง)"
echo "  $OUT/modules/    ← ko ทั้งหมด"
