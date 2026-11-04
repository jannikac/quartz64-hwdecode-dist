#!/usr/bin/env bash
set -euo pipefail

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(realpath "$here/..")
source_dir="$root/build/linux"
build_dir="$root/build/kernel"
stage_dir="$root/build/modules"
patch_dir="$root/patches"
repo=https://github.com/chewitt/linux.git
commit=2f895da2120e63197008b697ac26388c3dc4d742
export ARCH=arm64
export CROSS_COMPILE=${CROSS_COMPILE:-aarch64-unknown-linux-gnu-}
export KBUILD_BUILD_USER=quartz64
export KBUILD_BUILD_HOST=cross-build
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP="2026-10-28 00:00:00 UTC"
jobs=${JOBS:-$(nproc)}

make_kernel() {
    make -C "$source_dir" O="$build_dir" ARCH=arm64 \
        CROSS_COMPILE="$CROSS_COMPILE" "$@"
}

sha256sum -c <<EOF
8b377fa7419469ac8435dea04bb54b162e73eb7a8c0c6bdeee156965b04eda2c  $root/kernel.config
71eb6fb79038ad03ca87b3fdcd4a5de859562afb2d443ed6bcd76a785a3262e9  $root/patches/0001-rkvdec-initial-correctness.patch
603b209c56deb30fa65f329a5fe5a63384cbfd7a265a529e46e22bac358b6fdc  $root/patches/0002-rkvdec-vdpu346-recovery.patch
EOF

mkdir -p "$root/build"
if [ ! -d "$source_dir/.git" ]; then
    mkdir -p "$source_dir"
    git -C "$source_dir" init -q
    git -C "$source_dir" remote add origin "$repo"
fi

if [ "$(git -C "$source_dir" rev-parse --verify HEAD 2>/dev/null || true)" != "$commit" ]; then
    if ! git -C "$source_dir" fetch --depth 1 origin "$commit"; then
        git -C "$source_dir" fetch --filter=blob:none origin refs/heads/rockchip-7.3.y
    fi
    git -C "$source_dir" checkout --detach "$commit"
fi

test "$(git -C "$source_dir" rev-parse HEAD)" = "$commit" || {
    printf 'Kernel source is not at the pinned revision %s\n' "$commit" >&2
    exit 1
}

for patch in "$patch_dir"/0001-rkvdec-initial-correctness.patch \
             "$patch_dir"/0002-rkvdec-vdpu346-recovery.patch; do
    if git -C "$source_dir" apply --reverse --check "$patch" >/dev/null 2>&1; then
        printf 'Already applied: %s\n' "$(basename "$patch")"
    elif git -C "$source_dir" apply --check "$patch"; then
        git -C "$source_dir" apply "$patch"
        printf 'Applied: %s\n' "$(basename "$patch")"
    else
        printf 'Patch does not apply cleanly: %s\n' "$patch" >&2
        exit 1
    fi
done

rm -rf "$build_dir"
mkdir -p "$build_dir"
cp "$root/kernel.config" "$build_dir/.config"
make_kernel olddefconfig
make_kernel -j"$jobs" Image modules

release=$(cat "$build_dir/include/config/kernel.release")
out="$root/dist/$release"
rm -rf "$out" "$stage_dir"
mkdir -p "$out" "$stage_dir"

make_kernel INSTALL_MOD_PATH="$stage_dir" INSTALL_MOD_STRIP=1 \
    DEPMOD=depmod modules_install
tar --zstd --exclude="lib/modules/$release/build" \
    --exclude="lib/modules/$release/source" \
    -cf "$out/modules.tar.zst" -C "$stage_dir" "lib/modules/$release"

cp "$build_dir/arch/arm64/boot/Image" "$out/Image"
printf '%s\n' "$release" > "$out/kernel.release"
cp "$root/kernel.config" "$out/kernel.config"
git -C "$source_dir" rev-parse HEAD > "$out/source-revision"
(
    cd "$out"
    sha256sum Image modules.tar.zst kernel.release kernel.config source-revision \
        > SHA256SUMS
    sha256sum -c SHA256SUMS
)

printf '\nKernel artifacts: %s\n' "$out"
printf 'No DTB is built or copied. Deploy uses the board DTB.\n'
printf 'Next: sudo %s/deploy-kernel.sh --artifacts %s\n' "$here" "$out"
