#!/bin/sh
# Cross-build the patched libva-v4l2-request driver for the glibc Flatpak
# runtime used by VacuumTube, without installing the 1.7 GB Flatpak SDK on
# the board.
#
# Run this on a build host with an aarch64 glibc cross compiler.  On NixOS:
#
#   nix-shell -p pkgsCross.aarch64-multiplatform.stdenv.cc
#
# The headers must match the Flatpak runtime's UAPI/libva versions.  The
# easiest way to obtain them is to export them from the running board:
#
#   tar -C /usr/include -cf headers.tar va linux asm asm-generic libdrm
#
# and unpack that tar in $HEADERS on the build host.  The repo's linux/ tree
# can also be used for the kernel headers after `make headers_install`.
#
# Usage:
#   CROSS_CC=aarch64-unknown-linux-gnu-gcc \
#   HEADERS=/path/to/headers \
#   ./build-libva-cross.sh [OUTPUT_DIR]
#
# Environment:
#   CROSS_CC       cross compiler (default: aarch64-unknown-linux-gnu-gcc)
#   HEADERS        directory with va/, linux/, asm/, asm-generic/, libdrm/
#   VA_API_MINOR   Flatpak libva API minor (default: 22, runtime 25.08)
#   WORK           build directory (default: ~/.cache/vacuumtube-hwdecode)

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../env.sh"

cc=${CROSS_CC:-aarch64-unknown-linux-gnu-gcc}
headers=${HEADERS:-}
work=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/vacuumtube-hwdecode}
outdir=${1:-$work/glibc}
va_minor=${VA_API_MINOR:-22}
runtime_version=${RUNTIME_VERSION:-25.08}

src=$work/libva-v4l2-request-$LIBVA_FORK_COMMIT
tarball=$work/libva-v4l2-request.tar.gz
url=$LIBVA_FORK_URL/archive/$LIBVA_FORK_COMMIT.tar.gz

die() { printf '%s\n' "error: $*" >&2; exit 1; }

[ -n "$headers" ] || die "set HEADERS to a directory containing va/ and libdrm/"
[ -f "$headers/va/va.h" ] || die "$headers/va/va.h not found"
[ -f "$headers/libdrm/drm.h" ] || die "$headers/libdrm/drm.h not found"
[ -f "$headers/linux/videodev2.h" ] || die "$headers/linux/videodev2.h not found"
command -v "$cc" >/dev/null 2>&1 || die "$cc not found"

mkdir -p "$work"

if [ ! -f "$tarball" ]; then
	printf 'fetching %s\n' "$url"
	if command -v curl >/dev/null 2>&1; then
		curl -L --fail -o "$tarball" "$url"
	else
		wget -O "$tarball" "$url"
	fi
fi

rm -rf "$src"
mkdir -p "$src"
tar -C "$src" --strip-components=1 -xzf "$tarball"

for p in "$here/../patches/"*.patch; do
	printf 'applying %s\n' "$(basename "$p")"
	(cd "$src" && patch -p1 -f < "$p")
done

rm -rf "$outdir" "$work/headers-glibc"
mkdir -p "$outdir" "$work/headers-glibc"
cp -a "$headers"/. "$work/headers-glibc"/
# The driver reports the runtime's VA-API version; queryConfigProfiles and
# the init symbol must match the libva that dlopens it.
sed -i "s/^#define VA_MINOR_VERSION .*/#define VA_MINOR_VERSION    $va_minor/" \
	"$work/headers-glibc/va/va_version.h"

printf '#define VA_DRIVER_INIT_FUNC __vaDriverInit_1_%s\n' "$va_minor" \
	> "$outdir/autoconfig.h"

# shellcheck disable=SC2086
"$cc" -shared -fPIC -O2 -fvisibility=hidden -D_GNU_SOURCE -Wall \
	-I"$outdir" \
	-I"$src/include" -I"$src/src" \
	-I"$work/headers-glibc" -I"$work/headers-glibc/libdrm" \
	"$src"/src/*.c "$here/../init_compat.c" \
	-o "$outdir/$VA_DRIVER"

printf '\nBuilt %s\n' "$outdir/$VA_DRIVER"
echo "=== NEEDED ==="
readelf -d "$outdir/$VA_DRIVER" | grep -E 'NEEDED|SONAME' || true
echo "=== INIT SYMBOLS ==="
readelf -Ws "$outdir/$VA_DRIVER" | grep -E 'vaDriverInit' || true

cat <<EOF

Copy it to the board and enable the Flatpak override:

  scp "$outdir/$VA_DRIVER" user@board:/tmp/
  ssh user@board '/path/to/vacuumtube-vaapi/scripts/install-driver-override.sh /tmp/$VA_DRIVER'

The directory name is the runtime version ($runtime_version), not the VA-API
minor (currently 25.08 -> VA-API 1.22).
EOF
