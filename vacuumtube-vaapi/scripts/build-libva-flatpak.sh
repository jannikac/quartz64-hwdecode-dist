#!/bin/sh
# Build the patched libva-v4l2-request driver for the glibc Flatpak runtime
# used by VacuumTube and install it into the user's home as a read-only
# Flatpak filesystem override.
#
# Run this on the board, not on the build host.  It uses the installed
# org.freedesktop.Sdk matched to VacuumTube's runtime, so the driver links
# against the same libva/libdrm that Electron loads inside the sandbox.
#
# Usage:
#   ./build-libva-flatpak.sh
#
# Environment:
#   WORK           build directory (default: ~/.cache/vacuumtube-hwdecode)
#   KERNEL_HEADERS optional headers_install tree with newer V4L2 UAPI
#   RUNTIME_VERSION override the detected Flatpak runtime version

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../env.sh"

work=${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/vacuumtube-hwdecode}
src=$work/libva-v4l2-request-$LIBVA_FORK_COMMIT
tarball=$work/libva-v4l2-request.tar.gz
url=$LIBVA_FORK_URL/archive/$LIBVA_FORK_COMMIT.tar.gz

die() { printf '%s\n' "error: $*" >&2; exit 1; }

command -v flatpak >/dev/null 2>&1 || die "flatpak not found"

if ! flatpak info "$VACUUMTUBE_APP_ID" >/dev/null 2>&1; then
	die "$VACUUMTUBE_APP_ID is not installed"
fi

if [ -z "${RUNTIME_VERSION:-}" ]; then
	runtime_line=$(flatpak info "$VACUUMTUBE_APP_ID" |
		awk -F': ' '/^[[:space:]]*Runtime:/{print $2; exit}')
	[ -n "$runtime_line" ] ||
		die "could not determine VacuumTube's runtime"
	RUNTIME_VERSION=${runtime_line##*/}
fi

sdk_ref=$VACUUMTUBE_SDK//$RUNTIME_VERSION
if ! flatpak info "$sdk_ref" >/dev/null 2>&1; then
	if ! flatpak remotes --user 2>/dev/null | awk '{print $1}' |
		grep -qx flathub; then
		flatpak remote-add --user --if-not-exists flathub \
			https://flathub.org/repo/flathub.flatpakrepo
	fi
	printf 'installing %s\n' "$sdk_ref"
	flatpak install --user -y flathub "$sdk_ref"
fi

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

[ -f "$src/src/request.c" ] || die "source tree missing under $src"

for p in "$here/../patches/"*.patch; do
	printf 'applying %s\n' "$(basename "$p")"
	(cd "$src" && patch -p1 -f < "$p")
done

build=$work/build-flatpak-$RUNTIME_VERSION
root=$work/root-flatpak-$RUNTIME_VERSION
rm -rf "$build" "$root"

meson_extra=
if [ -n "${KERNEL_HEADERS:-}" ]; then
	rm -rf "$work/uapi"
	cp -a "$KERNEL_HEADERS" "$work/uapi"
	meson_extra="-Dkernel_headers=$work/uapi"
fi

cat > "$work/build-in-sdk.sh" <<EOF
set -eu
meson setup "$build" "$src" \\
	--prefix=/usr --libdir=lib --buildtype=release $meson_extra
ninja -C "$build"
DESTDIR="$root" ninja -C "$build" install
EOF

printf 'building inside %s\n' "$sdk_ref"
flatpak run --filesystem="$work" --command=sh "$sdk_ref" \
	"$work/build-in-sdk.sh"

driver=$root/usr/lib/dri/$VA_DRIVER
[ -f "$driver" ] || die "driver not produced: $driver"

dest=$HOME/.local/lib/v4l2-request-$RUNTIME_VERSION
install -Dm755 "$driver" "$dest/lib/dri/$VA_DRIVER"

# The driver is a no-op for other applications; only VacuumTube gets the
# environment and the read-only bind mount.
flatpak override --user \
	--filesystem="$dest:ro" \
	--env=LIBVA_DRIVER_NAME="$VA_DRIVER_NAME" \
	--env=LIBVA_DRIVERS_PATH="$dest/lib/dri" \
	"$VACUUMTUBE_APP_ID"

printf '\nInstalled %s\n' "$dest/lib/dri/$VA_DRIVER"
printf 'Applied Flatpak overrides for %s (runtime %s)\n' \
	"$VACUUMTUBE_APP_ID" "$RUNTIME_VERSION"

cat <<EOF

Next:
  $here/configure-vacuumtube.sh
  $here/check-vacuumtube-hw.sh

Notes:
  - Wayland is required for the zero-copy NV12 dmabuf path.  The Chromium
    flags written by configure-vacuumtube.sh select it.
  - A runtime update from \$RUNTIME_VERSION replaces the libva ABI.  Rerun
    this script after \`flatpak update\`.

EOF
