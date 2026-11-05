#!/bin/sh
# Cross-build FFmpeg 8.1.1 with the V4L2 Request hwaccel on an x86_64 host.
#
# Run from the repository root inside the ephemeral cross shell:
#
#   nix-shell
#   ./jellyfin-flatpak/cross-build-ffmpeg.sh
#
# The result is a small aarch64 tarball containing ffmpeg/ffprobe and the
# libav*/libsw* libraries.  It is used by scripts/test-cross-ffmpeg.sh on the
# board, which runs it against the KDE Flatpak runtime's glibc loader and
# proves that rkvdec is really decoding.
#
# Environment:
#   WORK   build directory (default: jellyfin-flatpak/cross-build)

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
work=${WORK:-$here/cross-build}
src=$work/ffmpeg-8.1.1
stage=$work/stage
out=$work/cross-ffmpeg-aarch64.tar.gz

: "${CROSS_CC:?run this inside: nix-shell (top-level shell.nix)}"
: "${CROSS_CXX:?run this inside: nix-shell}"
: "${CROSS_AR:?run this inside: nix-shell}"
: "${CROSS_RANLIB:?run this inside: nix-shell}"
: "${CROSS_STRIP:?run this inside: nix-shell}"
: "${CROSS_LINUX_HEADERS:?run this inside: nix-shell}"
: "${CROSS_PKG_CONFIG_PATH:?run this inside: nix-shell}"

command -v curl >/dev/null 2>&1 || {
	printf 'error: curl not found\n' >&2
	exit 1
}

mkdir -p "$work"
tarball=$work/ffmpeg-8.1.1.tar.xz
if [ ! -f "$tarball" ]; then
	curl -L --fail -o "$tarball" \
		https://ffmpeg.org/releases/ffmpeg-8.1.1.tar.xz
fi
printf '%s  %s\n' \
	b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3 \
	"$tarball" | sha256sum -c -

rm -rf "$src"
mkdir -p "$src"
tar -C "$src" --strip-components=1 -xf "$tarball"

for p in "$here"/patches/ffmpeg/*.patch; do
	printf 'applying %s\n' "$(basename "$p")"
	(cd "$src" && patch -p1 -f < "$p")
done
cp -a "$here/uapi-overlay" "$src/"

cd "$src"
env -u NIX_CFLAGS_COMPILE -u NIX_LDFLAGS \
	PKG_CONFIG_PATH="$CROSS_PKG_CONFIG_PATH" \
	PKG_CONFIG_LIBDIR="$CROSS_PKG_CONFIG_PATH" \
	./configure --prefix=/app \
	--enable-cross-compile --target-os=linux --arch=aarch64 \
	--cc="$CROSS_CC" --cxx="$CROSS_CXX" \
	--ar="$CROSS_AR" --ranlib="$CROSS_RANLIB" --strip="$CROSS_STRIP" \
	--disable-static --enable-shared --disable-stripping \
	--disable-doc --disable-htmlpages --disable-manpages \
	--disable-podpages --disable-txtpages \
	--enable-gpl --enable-version3 --enable-pthreads --enable-pic \
	--disable-autodetect --enable-zlib --enable-openssl --enable-libdrm --enable-libudev \
	--enable-v4l2_m2m --enable-v4l2-request \
	--extra-cflags="-I$PWD/uapi-overlay -I$CROSS_LINUX_HEADERS/include" \
	--extra-ldflags=-Wl,-rpath,/app/lib

make -j"${JOBS:-$(nproc)}"

rm -rf "$stage"
make install DESTDIR="$stage"

rm -f "$out"
tar -C "$stage/app" -czf "$out" bin/ffmpeg bin/ffprobe lib

printf '\nBuilt %s\n' "$out"
sha256sum "$out"
cat <<EOF

Copy it to the board and run the hardware test there:

  scp "$out" jannik@192.168.1.203:/tmp/
  scp "$here/scripts/test-cross-ffmpeg.sh" jannik@192.168.1.203:/tmp/
  ssh jannik@192.168.1.203 '
    rm -rf /tmp/cross-ffmpeg && mkdir -p /tmp/cross-ffmpeg
    tar -C /tmp/cross-ffmpeg -xzf /tmp/$(basename "$out")
    sh /tmp/test-cross-ffmpeg.sh'
EOF
