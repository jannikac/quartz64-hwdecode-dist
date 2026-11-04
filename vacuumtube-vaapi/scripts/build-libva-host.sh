#!/bin/sh
# Build the patched libva-v4l2-request VA-API driver for the running
# Alpine/postmarketOS host (musl).
#
# This is the bring-up/self-test build.  It lets the existing /opt/mpv-v4l2
# stack exercise the same driver that the Flatpak will later load, so a
# hardware or kernel problem is visible before Electron is involved.
#
# Usage:
#   ./build-libva-host.sh [PREFIX]
#
# Default PREFIX: /opt/libva-v4l2-request
#
# On postmarketOS/Alpine install the build dependencies first:
#   sudo apk add build-base meson linux-headers libva-dev libdrm-dev

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../env.sh"

prefix=${1:-/opt/libva-v4l2-request}
work=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/vacuumtube-hwdecode}
src=$work/libva-v4l2-request-$LIBVA_FORK_COMMIT
tarball=$work/libva-v4l2-request.tar.gz
url=$LIBVA_FORK_URL/archive/$LIBVA_FORK_COMMIT.tar.gz

die() { printf '%s\n' "error: $*" >&2; exit 1; }

for tool in meson ninja pkg-config cc; do
	command -v "$tool" >/dev/null 2>&1 ||
		die "$tool not found; install build-base meson linux-headers libva-dev libdrm-dev"
done

pkg-config --exists libva || die "libva development files not found"
pkg-config --exists libdrm || die "libdrm development files not found"

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

if [ ! -f "$src/src/request.c" ]; then
	die "source tree missing request.c under $src"
fi

for p in "$here/../patches/"*.patch; do
	printf 'applying %s\n' "$(basename "$p")"
	(cd "$src" && patch -p1 -f < "$p")
done

build=$work/build-host
rm -rf "$build" "$work/root-host"

meson_extra=
if [ -n "${KERNEL_HEADERS:-}" ]; then
	meson_extra="-Dkernel_headers=$KERNEL_HEADERS"
fi

# shellcheck disable=SC2086
meson setup "$build" "$src" \
	--prefix="$prefix" \
	--libdir=lib \
	--buildtype=release \
	$meson_extra
ninja -C "$build"
DESTDIR="$work/root-host" ninja -C "$build" install

printf '\nInstalled driver:\n'
find "$work/root-host$prefix/lib/dri" -maxdepth 1 -type f -name '*.so' -print

cat <<EOF

Install it on the host with root privileges:

  sudo mkdir -p "$(dirname "$prefix")"
  sudo cp -a "$work/root-host$prefix" "$prefix"

Self-test with the existing FFmpeg/mpv V4L2 stack:

  export LIBVA_DRIVER_NAME=$VA_DRIVER_NAME
  export LIBVA_DRIVERS_PATH=$prefix/lib/dri
  sudo apk add libva-utils   # only if vainfo is not installed
  vainfo --display drm --device /dev/dri/renderD128

  LD_LIBRARY_PATH=/opt/ffmpeg-v4l2/lib:/opt/mpv-v4l2/lib \\
    /opt/mpv-v4l2/bin/mpv --no-config --hwdec=vaapi-copy \\
    --vo=null --frames=120 /path/to/test.vp9.webm

Expected vainfo output includes:

  VAProfileVP9Profile0 : VAEntrypointVLD

EOF
