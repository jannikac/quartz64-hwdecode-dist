#!/bin/sh
# Run the packaged mpv/FFmpeg inside the Jellyfin Flatpak on a local file.
# This is a lower-level smoke test that does not need a Jellyfin login.
#
# Usage: test-flatpak-mpv.sh /path/to/local-test-file

set -eu

APP_ID=${JMP_APP_ID:-dev.jannik.JellyfinDesktopV4L2}
file=${1:-}
[ -n "$file" ] || {
	echo "usage: $0 /path/to/local-test-file" >&2
	exit 2
}
[ -f "$file" ] || {
	echo "error: no such file: $file" >&2
	exit 1
}

dir=$(dirname "$file")
flatpak run --filesystem="$dir:ro" --command=sh "$APP_ID" -c '
	log=/tmp/mpv-smoke.log
	rm -f "$log"
	mpv --no-config --hwdec=v4l2request-copy --vo=null --frames=120 \
		--log-file="$log" "$1" >/dev/null 2>&1 || true
	if grep -q "Using hardware decoding (v4l2request-copy)" "$log"; then
		echo "PASS: Using hardware decoding (v4l2request-copy)"
		grep -oE "Using (hardware|software) decoding[^ ]*( \([a-z0-9-]+\))?" "$log" | sort -u
		exit 0
	fi
	echo "FAIL: v4l2request hardware decode was not used"
	grep -oE "Using (hardware|software) decoding[^ ]*( \([a-z0-9-]+\))?" "$log" | sort -u || true
	tail -30 "$log" 2>/dev/null || true
	exit 1
' sh "$file"
