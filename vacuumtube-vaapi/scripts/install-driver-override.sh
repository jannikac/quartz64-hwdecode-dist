#!/bin/sh
# Install an already-built v4l2_request_drv_video.so for the Flathub
# VacuumTube app and apply the user Flatpak override.  The driver itself is
# built by build-libva-cross.sh or build-libva-flatpak.sh.
#
# Usage:
#   ./install-driver-override.sh /path/to/v4l2_request_drv_video.so
#
# Environment:
#   RUNTIME_VERSION  override the runtime version detected from VacuumTube

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../env.sh"

driver=${1:-}
[ -n "$driver" ] || {
	printf 'usage: %s /path/to/%s\n' "$0" "$VA_DRIVER" >&2
	exit 2
}
[ -f "$driver" ] || {
	printf 'error: driver not found: %s\n' "$driver" >&2
	exit 1
}

command -v flatpak >/dev/null 2>&1 || {
	printf 'error: flatpak not found\n' >&2
	exit 1
}
flatpak info "$VACUUMTUBE_APP_ID" >/dev/null 2>&1 || {
	printf 'error: %s is not installed\n' "$VACUUMTUBE_APP_ID" >&2
	exit 1
}

if [ -z "${RUNTIME_VERSION:-}" ]; then
	runtime_line=$(flatpak info "$VACUUMTUBE_APP_ID" |
		awk -F': ' '/^[[:space:]]*Runtime:/{print $2; exit}')
	[ -n "$runtime_line" ] || {
		printf 'error: could not determine the VacuumTube runtime\n' >&2
		exit 1
	}
	RUNTIME_VERSION=${runtime_line##*/}
fi

dest=$HOME/.local/lib/v4l2-request-$RUNTIME_VERSION
install -Dm755 "$driver" "$dest/lib/dri/$VA_DRIVER"

flatpak override --user \
	--filesystem="$dest:ro" \
	--env=LIBVA_DRIVER_NAME="$VA_DRIVER_NAME" \
	--env=LIBVA_DRIVERS_PATH="$dest/lib/dri" \
	"$VACUUMTUBE_APP_ID"

printf 'Installed %s\n' "$dest/lib/dri/$VA_DRIVER"
printf 'Applied the read-only filesystem and LIBVA_* overrides to %s\n' \
	"$VACUUMTUBE_APP_ID"
