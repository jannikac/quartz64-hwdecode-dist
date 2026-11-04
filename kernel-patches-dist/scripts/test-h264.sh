#!/bin/sh
# Hardware H.264 decode smoke test for the Quartz64 RK3568 rkvdec driver.
#
# Usage: test-h264.sh [FILE] [FRAMES]
#   FILE    H.264 .h264/.264/.avc, .mp4/.mov or .mkv/.webm input
#           (default: /home/jannik/test-claude/test.h264.mkv)
#   FRAMES  stop after this many decoded frames (default: 120)
#
# Set SINK=waylandsink (or autovideosink) to play the output on screen
# instead of the default fakesink test.
#
# Run on the board. Requires GStreamer v4l2codecs and a bound rkvdec device.

set -eu

codec=H.264
default=/home/jannik/test-claude/test.h264.mkv
suffix=h264dec

die() { printf '%s\n' "$*" >&2; exit 1; }

command -v gst-launch-1.0 >/dev/null 2>&1 || die "gst-launch-1.0 not found"

rkdev=
for name in /sys/class/video4linux/*/name; do
	[ -r "$name" ] || continue
	if [ "$(cat "$name")" = rkvdec ]; then
		rkdev=$(basename "$(dirname "$name")")
		break
	fi
done
[ -n "$rkdev" ] ||
	die "rkvdec video device not found; boot the 7.3 kernel or load the stock module"

find_dec() {
	for cand in "v4l2sl${rkdev}$1" "v4l2sl$1"; do
		if ! command -v gst-inspect-1.0 >/dev/null 2>&1 ||
		   gst-inspect-1.0 "$cand" >/dev/null 2>&1; then
			printf '%s\n' "$cand"
			return 0
		fi
	done
	return 1
}

dec=$(find_dec "$suffix") || die "$codec decoder not found"

file=${1:-$default}
frames=${2:-120}
[ -f "$file" ] || die "input not found: $file"
case "$frames" in
	''|*[!0-9]*|0) die "FRAMES must be a positive integer" ;;
esac

sink=${SINK:-fakesink}
if [ "$sink" = fakesink ]; then
	out="fakesink sync=false num-buffers=$frames"
else
	out="videoconvert ! identity eos-after=$frames ! $sink sync=true"
fi

case "${file##*.}" in
	h264|264|avc) demux='h264parse' ;;
	mp4|mov)      demux='qtdemux ! h264parse' ;;
	mkv|webm)     demux='matroskademux ! h264parse' ;;
	*) die "unsupported extension: $file" ;;
esac

printf 'H.264 hardware decode: %s (limit %s frames)\n' "$file" "$frames"
if gst-launch-1.0 -e filesrc location="$file" ! $demux ! "$dec" ! $out; then
	printf 'PASS: %s hardware decode\n' "$codec"
else
	printf 'FAIL: %s hardware decode\n' "$codec" >&2
	exit 1
fi
