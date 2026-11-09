#!/bin/sh
# Exercise the patched driver through the already-working /opt FFmpeg/mpv
# V4L2 stack.  This validates VA-API + rkvdec on the board before the
# Flatpak/Electron step.
#
# Usage: test-vaapi-host.sh [PREFIX] [VP9_FILE]

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../env.sh"

prefix=${1:-/opt/libva-v4l2-request}
file=${2:-/home/<user>/test-claude/test.vp9.webm}

export LIBVA_DRIVER_NAME="$VA_DRIVER_NAME"
export LIBVA_DRIVERS_PATH="$prefix/lib/dri"

[ -f "$prefix/lib/dri/$VA_DRIVER" ] || {
	printf 'missing %s\n' "$prefix/lib/dri/$VA_DRIVER" >&2
	exit 1
}

if command -v vainfo >/dev/null 2>&1; then
	echo "====VAINFO===="
	vainfo --display drm --device /dev/dri/renderD128 || true
else
	echo "vainfo not installed (apk add libva-utils)"
fi

[ -f "$file" ] || {
	printf 'input not found: %s\n' "$file" >&2
	exit 1
}

[ -x /opt/mpv-v4l2/bin/mpv ] || {
	printf '/opt/mpv-v4l2/bin/mpv not found\n' >&2
	exit 1
}

echo "====MPV VAAPI COPY===="
rm -f /tmp/vaapi-mpv.log
LD_LIBRARY_PATH=/opt/ffmpeg-v4l2/lib:/opt/mpv-v4l2/lib \
	/opt/mpv-v4l2/bin/mpv \
	--no-config --hwdec=vaapi-copy --vo=null --frames=120 \
	--log-file=/tmp/vaapi-mpv.log "$file"

grep -oE 'Using (hardware|software) decoding[^ ]*( \([a-z0-9-]+\))?' \
	/tmp/vaapi-mpv.log | sort | uniq -c || true

cat <<'EOF'

Expected:
  1 Using hardware decoding (vaapi-copy)

If it says software or fails, inspect /tmp/vaapi-mpv.log before touching
VacuumTube.  The Flatpak build uses the same driver source and kernel API.
EOF
