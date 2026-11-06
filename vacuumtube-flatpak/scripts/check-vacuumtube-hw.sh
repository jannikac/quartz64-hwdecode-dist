#!/bin/sh
# Report whether the forked VacuumTube's Chromium GPU process loaded the
# bundled VA-API driver and whether rkvdec is actually working while a video
# plays.
#
# Unlike ../vacuumtube-vaapi/scripts/check-vacuumtube-hw.sh, the driver lives
# inside /app and the LIBVA_* environment is part of the app manifest, so this
# checks the installed app rather than a user override.
#
# No Jellyfin/YouTube identifiers, URLs or titles are queried.

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../env.sh"

echo "====PERMISSIONS===="
permissions=$(flatpak info --user --show-permissions "$APP_ID" 2>/dev/null ||
	flatpak info --show-permissions "$APP_ID" 2>/dev/null || true)
printf '%s\n' "$permissions"

env_ok=0
if printf '%s\n' "$permissions" |
	grep -q "LIBVA_DRIVER_NAME=$VA_DRIVER_NAME" &&
   printf '%s\n' "$permissions" |
	grep -q "LIBVA_DRIVERS_PATH=$VA_DRIVERS_PATH"; then
	env_ok=1
fi
[ "$env_ok" -eq 1 ] || echo "LIBVA_* environment not found in app permissions"

echo "====DRIVER===="
app_location=$(flatpak info --user --show-location "$APP_ID" 2>/dev/null ||
	flatpak info --show-location "$APP_ID" 2>/dev/null || true)
if [ -n "$app_location" ] && [ -f "$app_location/files/lib/dri/$VA_DRIVER" ]; then
	ls -l "$app_location/files/lib/dri/$VA_DRIVER"
else
	echo "driver not found in the installed app (expected /app/lib/dri/$VA_DRIVER)"
fi

echo "====APP PIDS===="
flatpak ps --columns=application,pid,child-pid 2>/dev/null |
	awk -v app="$APP_ID" '$1 == app {print}'

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
grep -iE "rkvdec|video-codec|fdf80200" /proc/interrupts 2>/dev/null || echo "no rkvdec line in /proc/interrupts"

irq_sum() {
	grep -iE "rkvdec|video-codec|fdf80200" /proc/interrupts 2>/dev/null |
		awk '{for (i = 2; i <= NF; i++) if ($i ~ /^[0-9]+$/) s += $i}
		     END {print s + 0}'
}

before=$(irq_sum)
sleep 5
after=$(irq_sum)
printf 'rkvdec IRQ delta over 5 s: %s\n' "$((after - before))"

rc=0
[ "$env_ok" -eq 1 ] || rc=1
[ "$driver_found" -eq 1 ] || rc=1
[ "$fd_found" -eq 1 ] || rc=1
[ "$after" -gt "$before" ] || rc=1
if [ "$rc" -eq 0 ]; then
	echo "PASS: LIBVA_* baked in, driver mapped, V4L2 nodes open, rkvdec IRQs advancing"
else
	echo "FAIL: expected baked-in LIBVA_* env, driver mapping, open /dev/video* nodes and a non-zero rkvdec IRQ delta"
fi

cat <<'EOF'

Expected while a VP9 video is playing:
  - app permissions contain LIBVA_DRIVER_NAME and LIBVA_DRIVERS_PATH
  - /app/lib/dri/v4l2_request_drv_video.so appears in the GPU process maps
  - a process holds /dev/videoN (rkvdec) and a /dev/mediaN node
  - the rkvdec IRQ delta is non-zero
  - `--debug-gpu` shows "Video Decode: Hardware accelerated"
EOF

exit "$rc"
