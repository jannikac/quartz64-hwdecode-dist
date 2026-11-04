#!/bin/sh
# Remove the VacuumTube VA-API override and driver.  The app itself, its
# config and its Flatpak runtime are left installed.

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../env.sh"

# Remove only the variables we added; leave any other user overrides alone.
flatpak override --user --unset-env=LIBVA_DRIVER_NAME "$VACUUMTUBE_APP_ID" || true
flatpak override --user --unset-env=LIBVA_DRIVERS_PATH "$VACUUMTUBE_APP_ID" || true

for d in "$HOME"/.local/lib/v4l2-request-*; do
	[ -d "$d" ] || continue
	flatpak override --user --nofilesystem="$d" "$VACUUMTUBE_APP_ID" || true
	rm -rf "$d"
	printf 'removed %s\n' "$d"
done

printf 'Removed VacuumTube VA-API overrides.\n'
