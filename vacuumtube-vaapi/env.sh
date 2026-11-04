# shellcheck disable=SC2034
# Shared pins for the VacuumTube VA-API stack.
#
# This file is sourced by the scripts in this directory.  Keep the commit
# pinned: the driver patches are generated against exactly this revision.

LIBVA_FORK_URL=https://github.com/dongioia/libva-v4l2-request
LIBVA_FORK_COMMIT=ed4bc90a8c979c83790013297850960c73a3d2f1

VACUUMTUBE_APP_ID=rocks.shy.VacuumTube
VACUUMTUBE_RUNTIME=org.freedesktop.Platform
VACUUMTUBE_SDK=org.freedesktop.Sdk

VA_DRIVER=v4l2_request_drv_video.so
VA_DRIVER_NAME=v4l2_request
