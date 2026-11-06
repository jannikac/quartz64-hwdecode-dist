# shellcheck disable=SC2034
# Shared pins for the forked VacuumTube V4L2 Flatpak.
#
# Keep these in sync with dev.jannik.VacuumTubeV4L2.yml and
# ../vacuumtube-vaapi/env.sh.  The driver patches are generated against the
# pinned fork commit.

APP_ID=dev.jannik.VacuumTubeV4L2

LIBVA_FORK_URL=https://github.com/dongioia/libva-v4l2-request
LIBVA_FORK_COMMIT=ed4bc90a8c979c83790013297850960c73a3d2f1

VACUUMTUBE_COMMIT=665ca9b4c30add776fba948f8b0262fe0ce30178
VACUUMTUBE_VERSION=2.0.1
ELECTRON_VERSION=44.5.1

RUNTIME_VERSION=25.08
LIBVA_VERSION=2.22.0
VA_API_MINOR=22

VA_DRIVER=v4l2_request_drv_video.so
VA_DRIVER_NAME=v4l2_request
VA_DRIVERS_PATH=/app/lib/dri
