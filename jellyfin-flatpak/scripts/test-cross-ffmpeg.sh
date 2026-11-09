#!/bin/sh
# Run a cross-built FFmpeg against the board's rkvdec using the KDE Flatpak
# runtime's glibc loader.  This is the cross-compile hardware test: no build
# happens on the board.
#
# Usage:
#   test-cross-ffmpeg.sh [/tmp/cross-ffmpeg] [/path/to/local-vp9-file]
#
# The runtime loader is used explicitly because the host root is musl while
# the cross-compiled binaries target glibc.

set -eu

dir=${1:-/tmp/cross-ffmpeg}
file=${2:-/home/<user>/test-claude/test.vp9.webm}
runtime=$(find /var/lib/flatpak/runtime/org.kde.Platform/aarch64/6.11 \
	-maxdepth 3 -type d -name files | head -1)

[ -n "$runtime" ] || {
	echo "FAIL: org.kde.Platform//6.11 runtime not found" >&2
	exit 1
}
[ -x "$dir/bin/ffmpeg" ] || {
	echo "FAIL: missing $dir/bin/ffmpeg (untar the cross build first)" >&2
	exit 1
}
[ -f "$file" ] || {
	echo "FAIL: test file not found: $file" >&2
	exit 1
}

loader=$runtime/lib/ld-linux-aarch64.so.1
export LD_LIBRARY_PATH=$dir/lib:$runtime/lib/aarch64-linux-gnu:$runtime/lib

irq_sum() {
	grep -i rkvdec /proc/interrupts 2>/dev/null |
		awk '{for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+$/) s += $i}
		     END {print s + 0}'
}

echo "=====HWACCELS====="
"$loader" "$dir/bin/ffmpeg" -hide_banner -hwaccels |
	grep -E 'v4l2request' || {
		echo "FAIL: cross-built FFmpeg has no v4l2request hwaccel" >&2
		exit 1
	}

echo "=====DECODE====="
log=/tmp/cross-ffmpeg-decode.log
rm -f "$log"
before=$(irq_sum)
set +e
"$loader" "$dir/bin/ffmpeg" -hide_banner -loglevel info -y \
	-hwaccel v4l2request -hwaccel_output_format drm_prime \
	-i "$file" -frames:v 120 -f null - >"$log" 2>&1
rc=$?
set -e
after=$(irq_sum)

grep -Ei 'Using V4L2 media driver rkvdec|v4l2|rkvdec|error|failed' "$log" |
	tail -20 || true
printf 'decode_rc = %s\n' "$rc"
printf 'rkvdec_irq_delta_decode = %s\n' "$((after - before))"

if [ "$rc" -eq 0 ] &&
   grep -q 'Using V4L2 media driver rkvdec' "$log" &&
   [ "$after" -gt "$before" ]; then
	echo "PASS: cross-built FFmpeg decoded with rkvdec"
	exit 0
fi
echo "FAIL: cross-built FFmpeg did not use rkvdec"
exit 1
