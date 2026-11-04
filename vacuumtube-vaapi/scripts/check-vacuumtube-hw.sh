#!/bin/sh
# Report whether VacuumTube's Chromium GPU process loaded the VA-API driver
# and whether rkvdec is actually working while a video plays.
#
# No Jellyfin/YouTube identifiers, URLs or titles are queried.

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../env.sh"

# shellcheck disable=SC2125
driver_path=$HOME/.local/lib/v4l2-request-*/lib/dri/$VA_DRIVER

echo "====OVERRIDES===="
flatpak override --user --show "$VACUUMTUBE_APP_ID" 2>/dev/null || true

echo "====DRIVER===="
# shellcheck disable=SC2086
ls -l $driver_path 2>/dev/null || echo "driver not installed"

echo "====APP PIDS===="
flatpak ps --columns=application,pid,child-pid 2>/dev/null |
	awk -v app="$VACUUMTUBE_APP_ID" '$1 == app {print}'

echo "====DRIVER MAPPED IN PROCESSES===="
driver_found=0
for maps in /proc/[0-9]*/maps; do
	[ -r "$maps" ] || continue
	pid=${maps#/proc/}
	pid=${pid%/maps}
	if grep -qs "$VA_DRIVER" "$maps"; then
		cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-160)
		printf 'pid %s: %s\n' "$pid" "$cmd"
		driver_found=1
	fi
done
[ "$driver_found" -eq 1 ] || echo "driver not mapped (is a video playing?)"

echo "====V4L2 FDS===="
fd_found=0
for fd in /proc/[0-9]*/fd/*; do
	link=$(readlink "$fd" 2>/dev/null) || continue
	case "$link" in
	/dev/video*|/dev/media*)
		pid=${fd#/proc/}
		pid=${pid%%/*}
		cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-100)
		printf 'pid %s: %s -> %s\n' "$pid" "$cmd" "$link"
		fd_found=1
		;;
	esac
done
[ "$fd_found" -eq 1 ] || echo "no process has /dev/video* or /dev/media* open"

echo "====RKVDEC IRQ===="
grep -i rkvdec /proc/interrupts 2>/dev/null || echo "no rkvdec line in /proc/interrupts"

irq_sum() {
	grep -i rkvdec /proc/interrupts 2>/dev/null |
		awk '{for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+$/) s += $i}
		     END {print s + 0}'
}

before=$(irq_sum)
sleep 5
after=$(irq_sum)
printf 'rkvdec IRQ delta over 5 s: %s\n' "$((after - before))"

rc=0
[ "$driver_found" -eq 1 ] || rc=1
[ "$fd_found" -eq 1 ] || rc=1
[ "$after" -gt "$before" ] || rc=1
if [ "$rc" -eq 0 ]; then
	echo "PASS: driver mapped, V4L2 nodes open, rkvdec IRQs advancing"
else
	echo "FAIL: expected driver mapping, open /dev/video* nodes and a non-zero rkvdec IRQ delta"
fi

cat <<'EOF'

Expected while a VP9 video is playing:
  - the driver .so appears in the GPU process maps
  - a process holds /dev/videoN (rkvdec) and a /dev/mediaN node
  - the rkvdec IRQ delta is non-zero
  - `--debug-gpu` shows "Video Decode: Hardware accelerated"
EOF

exit "$rc"
