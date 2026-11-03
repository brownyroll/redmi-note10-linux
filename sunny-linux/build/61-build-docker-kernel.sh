#!/usr/bin/env bash
# Rebuild the NetErnels v7 kernel with the missing Docker features.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUNNY_ROOT="${SUNNY_ROOT:-/root/sunny}"
K="$SUNNY_ROOT/src/kernel"
OUT="$SUNNY_ROOT/out-docker-v7-eva2"
WIN="/mnt/c/Users/brown/Documents/Default Project/sunny-linux/out"
MKBOOTIMG="$SUNNY_ROOT/tools/mkbootimg/mkbootimg.py"
TC64="$SUNNY_ROOT/toolchains/eva-gcc64"
TC32="$SUNNY_ROOT/toolchains/eva-gcc32"
SOURCE_PATCHES=(
  "$HERE/patches/0001-qg-complete-fallback-profile-selection.patch"
  "$HERE/patches/0002-ikconfig-embed-actual-build-config.patch"
  "$HERE/patches/0003-qg-reject-stale-shutdown-soc.patch"
)

[ -d "$K/.git" ] || { echo "missing kernel source: $K" >&2; exit 1; }
[ "$(git -C "$K" rev-parse HEAD)" = 6f0680fc1070e4717f27749a656ac28bf278c1ca ] || {
  echo 'kernel source commit does not match NetErnels 7.0 base' >&2; exit 1;
}
[ -x "$TC64/bin/aarch64-elf-gcc" ] || { echo "missing Eva GCC64: $TC64" >&2; exit 1; }
[ -x "$TC32/bin/arm-eabi-gcc" ] || { echo "missing Eva GCC32: $TC32" >&2; exit 1; }

# Keep source fixes reproducible and idempotent: repair the sunny DS28E16
# fallback and make /proc/config.gz describe the kernel actually built.
for source_patch in "${SOURCE_PATCHES[@]}"; do
  [ -f "$source_patch" ] || { echo "missing source patch: $source_patch" >&2; exit 1; }
  if git -C "$K" apply --reverse --check "$source_patch" 2>/dev/null; then
    echo "source patch already applied: ${source_patch##*/}"
  else
    git -C "$K" apply --check "$source_patch"
    git -C "$K" apply "$source_patch"
  fi
done

mkdir -p "$OUT" "$WIN"
export ARCH=arm64 SUBARCH=arm64
export PATH="$TC32/bin:$TC64/bin:/usr/bin:$PATH"
export CROSS_COMPILE=aarch64-elf-
export CROSS_COMPILE_ARM32=arm-eabi-
export CC=aarch64-elf-gcc
export LD="$TC64/bin/aarch64-elf-ld.lld"
export AR=llvm-ar NM=llvm-nm OBJDUMP=llvm-objdump OBJCOPY=llvm-objcopy
export OBJSIZE=llvm-objsize STRIP=llvm-strip HOSTAR=llvm-ar HOSTCC=gcc
export KBUILD_BUILD_USER=phonesunny KBUILD_BUILD_HOST=brownyrollz
export KCFLAGS='-Wno-error -Wno-array-bounds -Wno-stringop-overflow -Wno-dangling-pointer -Wno-use-after-free -Wno-format-overflow'

kmake() {
  make O="$OUT" ARCH=arm64 \
    CROSS_COMPILE=aarch64-elf- CROSS_COMPILE_ARM32=arm-eabi- \
    CC=aarch64-elf-gcc LD="$TC64/bin/aarch64-elf-ld.lld" \
    AR=llvm-ar NM=llvm-nm OBJDUMP=llvm-objdump OBJCOPY=llvm-objcopy \
    OBJSIZE=llvm-objsize STRIP=llvm-strip HOSTAR=llvm-ar HOSTCC=gcc "$@"
}

cd "$K"
if [ "${FINAL_ONLY:-0}" != 1 ]; then
  kmake neternels_defconfig

  # Keep a bootable control image built from the real NetErnels v7 defconfig
  # and the hardware fix, but without the Docker delta.  This separates
  # hardware and toolchain problems from the container feature set.
  kmake -j"$(nproc)" Image dtbs 2>&1 | tee "$OUT/build-baseline.log"
  cp "$OUT/arch/arm64/boot/Image" "$OUT/Image-baseline"
  python3 "$MKBOOTIMG" --header_version 4 \
    --kernel "$OUT/Image-baseline" \
    --os_version 16.0.0 --os_patch_level 2026-05 \
    --cmdline '' -o "$OUT/boot-neternels-baseline.img"
else
  [ -f "$OUT/.config" ] || { echo 'FINAL_ONLY requires an existing output config' >&2; exit 1; }
  [ -f "$OUT/Image-baseline" ] || { echo 'FINAL_ONLY requires the completed baseline artifact' >&2; exit 1; }
  echo 'Reusing completed baseline; rebuilding only the final Docker image'
fi

cp "$HERE/docker-kernel.fragment" "$OUT/docker-kernel.fragment"
scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" "$OUT/docker-kernel.fragment"
kmake olddefconfig

# This 4.14 tree does not reliably invalidate the embedded IKCONFIG payload
# when an existing O= directory receives a merged fragment.  Regenerate it so
# /proc/config.gz describes the kernel that was actually compiled.
rm -f "$OUT/kernel/config_data.gz" "$OUT/kernel/config_data.h"

required=(CGROUP_DEVICE CGROUP_PIDS MEMCG PID_NS IPC_NS USER_NS POSIX_MQUEUE VETH BRIDGE OVERLAY_FS SECCOMP_FILTER)
for key in "${required[@]}"; do
  grep -q "^CONFIG_${key}=y$" "$OUT/.config" || { echo "CONFIG_${key} was not enabled" >&2; exit 1; }
done

kmake -j"$(nproc)" Image dtbs 2>&1 | tee "$OUT/build.log"
cp "$OUT/arch/arm64/boot/Image" "$OUT/Image"

python3 "$MKBOOTIMG" --header_version 4 \
  --kernel "$OUT/Image" \
  --os_version 16.0.0 --os_patch_level 2026-05 \
  --cmdline '' -o "$OUT/boot-docker-test.img"

cp "$OUT/Image" "$WIN/Image-docker"
cp "$OUT/.config" "$WIN/config-docker"
cp "$OUT/boot-docker-test.img" "$WIN/boot-docker-test.img"
cp "$OUT/Image-baseline" "$WIN/Image-neternels-baseline"
cp "$OUT/boot-neternels-baseline.img" "$WIN/boot-neternels-baseline.img"
{
  git -C "$K" rev-parse HEAD
  "$TC64/bin/aarch64-elf-gcc" --version | head -n 1
  "$TC64/bin/aarch64-elf-ld.lld" --version | head -n 1
  sha256sum "$OUT/Image-baseline" "$OUT/boot-neternels-baseline.img"
  sha256sum "$OUT/Image" "$OUT/boot-docker-test.img"
  strings "$OUT/Image" | grep -m1 'Linux version' || true
} | tee "$OUT/docker-kernel-build.txt" | tee "$WIN/docker-kernel-build.txt"
