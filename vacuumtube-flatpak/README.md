# VacuumTube V4L2 Flatpak (personal fork)

This directory builds a **personal, sideloaded** Flatpak of VacuumTube 2.0.1
with the `libva-v4l2-request` VA-API driver built in for the Pine64 Quartz64
Model B (RK3566 / `rkvdec`).  The driver and the `LIBVA_*` environment are part
of the app, so there is no post-install `flatpak override` step.

> **Not for Flathub. Not affiliated with VacuumTube.**  This is a fork of the
> real Flathub manifest under a different app ID, `dev.jannik.VacuumTubeV4L2`.
> Do not submit it to Flathub and do not present it as the official app.  The
> real app is `rocks.shy.VacuumTube`; both can be installed side by side.

The app source is MIT-licensed VacuumTube by shy:
<https://github.com/shy1132/VacuumTube>.  A copy of the upstream license is in
`LICENSE`.

## Two options: keep this or use `../vacuumtube-vaapi/`

Both directories make VacuumTube use the RK3566 VA-API driver.  They solve the
problem differently, and the tradeoff is real:

| | `../vacuumtube-vaapi/` | `vacuumtube-flatpak/` (this directory) |
|---|---|---|
| VacuumTube build | Official Flathub `rocks.shy.VacuumTube`, untouched | Personal fork `dev.jannik.VacuumTubeV4L2` |
| Driver location | User override at `~/.local/lib/v4l2-request-<runtime>/lib/dri` | Baked into `/app/lib/dri` |
| Install steps | Install official app, then run two scripts (install driver + configure) | Install one `.flatpak` bundle (plus app settings) |
| App updates | Automatic from Flathub | **Manual** rebuild and reinstall for every upstream VacuumTube release |
| Runtime/ABI updates | Rebuild only the small driver `.so` | Rebuild the whole Electron app plus driver |
| Best for | Normal day-to-day use; least maintenance | A single self-contained artifact; no override scripts |

`../vacuumtube-vaapi/` is deliberately kept and is not replaced by this fork.
The official app's automatic updates and the small driver-only rebuild are
genuine advantages.  This fork trades those for one bundled artifact.  A future
reader should choose based on which side of that tradeoff matters more.

## What is pinned

| Input | Pin |
|---|---|
| Flathub manifest source | `flathub/rocks.shy.VacuumTube` commit `74020459deda4eb62f729bd25d42e5a65aae8719` (merge of "bump to 2.0.1") |
| VacuumTube source | commit `665ca9b4c30add776fba948f8b0262fe0ce30178`, version 2.0.1 |
| Electron / Chromium | Electron `44.5.1`, Chromium `152.0.7977.130` |
| Runtime / base | `org.freedesktop.Platform//25.08`, `org.electronjs.Electron2.BaseApp//25.08` |
| SDK / extension | `org.freedesktop.Sdk//25.08`, `org.freedesktop.Sdk.Extension.node22//25.08` |
| VA-API driver fork | `dongioia/libva-v4l2-request` commit `ed4bc90a8c979c83790013297850960c73a3d2f1` |
| Driver source archive SHA-256 | `e4cb31aba67d0121dd294e315df5fba63ebf41f7d1d2dd7f5ccf8f3ebfb333a5` |
| npm/Electron sources | `flatpak-sources.json`, copied from the pinned Flathub commit |
| Target | aarch64, RK3566 `rkvdec` (VDPU346) |

The npm dependency list is **not** hand-written.  `flatpak-sources.json` comes
from the upstream Flathub manifest, which was generated with
`flatpak-node-generator`.  Regenerate it with that tool when bumping the
VacuumTube source; do not edit it by hand.

## Intended fork drift from upstream

The manifest is kept as close to upstream as practical.  The only deliberate
differences are:

1. App ID changed to `dev.jannik.VacuumTubeV4L2`.
2. Own desktop file and AppStream metadata under the new ID.  The icon is the
   real upstream `assets/icon.svg` from the cloned VacuumTube source, just
   installed under this app's icon ID instead of `rocks.shy.VacuumTube`'s, so
   the two launcher entries still do not collide at the ID/export level even
   though they look the same.
3. A `libva-v4l2-request` module that installs `/app/lib/dri/v4l2_request_drv_video.so`.
4. Two `finish-args` entries:
   `--env=LIBVA_DRIVER_NAME=v4l2_request` and
   `--env=LIBVA_DRIVERS_PATH=/app/lib/dri`.
5. The app module installs the personal metadata files instead of upstream's.

Everything else is upstream, including all existing finish-args.  Upstream
already grants `--device=all` for the GPU and controllers, which covers the
`/dev/video*` and `/dev/media*` media-controller nodes that `rkvdec` needs.
This fork **keeps** that line; it does not replace it with `--device=dri`.

Check the drift yourself before changing the manifest:

```sh
git clone https://github.com/flathub/rocks.shy.VacuumTube
git -C rocks.shy.VacuumTube checkout 74020459deda4eb62f729bd25d42e5a65aae8719
diff -u rocks.shy.VacuumTube/rocks.shy.VacuumTube.yml \
  vacuumtube-flatpak/dev.jannik.VacuumTubeV4L2.yml
```

The expected output is only the app-ID/metadata changes, the driver module, and
the two `LIBVA_*` lines.  If upstream source changes appear in that diff, the
fork dropped something by accident.

## VA-API version compatibility

This was checked against the runtime pinned by this manifest, not assumed from
`../vacuumtube-vaapi/env.sh`.

- `org.freedesktop.Platform//25.08` ships `libva.so.2.2200.0` on both aarch64
  and x86_64 (libva 2.22.0, VA-API 1.22).
- The matching `org.freedesktop.Sdk//25.08` reports `pkg-config libva 1.22.0`,
  so the driver's meson build generates `__vaDriverInit_1_22` as its primary
  entry point.
- The driver was built against the real `org.freedesktop.Sdk//25.08` during
  this fork's preparation.  It installed
  `/app/lib/dri/v4l2_request_drv_video.so` and exported
  `__vaDriverInit_1_22` plus the `1_23`, `1_24` and `1_25` wrappers from
  `init_compat.c`.

`init_compat.c` is still hardcoded to make the 1.22 entry point primary.  That
is correct for runtime 25.08.  If a future runtime changes the libva ABI, rebuild
the Flatpak; if the new API minor is above 1.25, add the new wrapper in
`init_compat.c` before rebuilding.

## Driver patches

Patches `0001`–`0005` are copied verbatim from
`../vacuumtube-vaapi/patches/`; they are not rewritten here.  `0006` is
fork-local build glue for this manifest.

| Patch | Purpose |
|---|---|
| `0001-libva-v4l2-request-autodetect-rkvdec.patch` | Find `/dev/videoN` and `/dev/mediaN` by the `rkvdec` name instead of assuming `video0`/`media0`. |
| `0002-libva-v4l2-request-vp9-profile0-only.patch` | Advertise only VP9 Profile 0. |
| `0003-libva-v4l2-request-reduce-frame-pool.patch` | Reduce the V4L2 capture pool from 64 to 32 buffers. |
| `0004-libva-v4l2-request-bind-on-export.patch` | Bind a CAPTURE buffer when Chromium exports a VA surface. |
| `0005-libva-v4l2-request-export-separate-layers.patch` | Honour `VA_EXPORT_SURFACE_SEPARATE_LAYERS` with one plane per layer. |
| `0006-libva-v4l2-request-build-init-compat.patch` | Fork-local build glue: add `init_compat.c` to the driver's meson source list. |

See `../vacuumtube-vaapi/README.md` for the longer explanation of each driver
patch and the RK3566 codec limitations.

## Build

Build on an aarch64 host, or on x86_64 with aarch64 binfmt/qemu-user configured.
This build runs Electron's npm/electron-builder pipeline; it does not use the
custom cross-toolchain path from `../jellyfin-flatpak/`.

The board itself is usually a poor build host because the SDK and build tree
need several GB of free space.  Build elsewhere and copy only the bundle.

```sh
cd quartz64-hwdecode-dist/vacuumtube-flatpak

flatpak remote-add --user --if-not-exists flathub \
  https://flathub.org/repo/flathub.flatpakrepo

./scripts/build-flatpak.sh
# On an x86_64 host with aarch64 binfmt:
# ARCH=aarch64 ./scripts/build-flatpak.sh
```

The script installs missing runtimes from Flathub, builds the manifest, and
exports:

```text
dist/dev.jannik.VacuumTubeV4L2.flatpak
dist/dev.jannik.VacuumTubeV4L2.flatpak.sha256
```

It needs `flatpak-builder`, `flatpak`, and enough space for the SDK/base app and
build tree.  The exact pins and permissions remain in
`dev.jannik.VacuumTubeV4L2.yml`.

## Install

Copy only the bundle to the board:

```sh
scp dist/dev.jannik.VacuumTubeV4L2.flatpak \
  jannik@192.168.1.130:/tmp/

ssh jannik@192.168.1.130 '
  flatpak install --user --noninteractive \
    /tmp/dev.jannik.VacuumTubeV4L2.flatpak
'
```

If the runtime/base app are not already present, install them from Flathub
first:

```sh
flatpak install --user flathub \
  org.freedesktop.Platform//25.08 \
  org.electronjs.Electron2.BaseApp//25.08 \
  org.freedesktop.Sdk.Extension.node22//25.08
```

Run it from the desktop entry or directly:

```sh
flatpak run dev.jannik.VacuumTubeV4L2
```

The official `rocks.shy.VacuumTube` app, if installed, is not modified.

### Configure the app

The driver and `LIBVA_*` environment are already baked in.  The remaining
configuration is VacuumTube's own Chromium flags and codec settings.  On the
board, as the desktop user:

```sh
./scripts/configure-vacuumtube.sh
```

This writes `~/.var/app/dev.jannik.VacuumTubeV4L2/config/VacuumTube/flags.txt`
and enables `hardware_decoding` plus the VP9-only codec filter in `config.json`.
It backs up existing files first.  If `jq` is unavailable, it prints the
settings to change manually instead of overwriting `config.json`.

A Wayland session is required for the zero-copy NV12 path.

## Verification

Play a VP9 video, then run:

```sh
./scripts/check-vacuumtube-hw.sh
```

The script uses the new app ID and reports:

- the app's installed permissions, including the baked-in `LIBVA_*` entries;
- the bundled driver at the app's `/app/lib/dri` path;
- processes that mapped `v4l2_request_drv_video.so`;
- open `/dev/video*` and `/dev/media*` descriptors;
- the `rkvdec` interrupt delta over five seconds.

Expected while a VP9 video is playing:

```text
LIBVA_DRIVER_NAME=v4l2_request
LIBVA_DRIVERS_PATH=/app/lib/dri
...
v4l2_request_drv_video.so appears in a GPU process
/dev/videoN (rkvdec) and /dev/mediaN are open
rkvdec IRQ delta over 5 s: <non-zero>
PASS: LIBVA_* baked in, driver mapped, V4L2 nodes open, rkvdec IRQs advancing
```

The script deliberately does not query titles, file paths, or stream URLs.

For Chromium's own view:

```sh
flatpak run --command=startvacuumtube dev.jannik.VacuumTubeV4L2 --debug-gpu
```

Expected in `chrome://gpu`:

```text
Video Decode: Hardware accelerated
```

### Local VP9 test without a YouTube login

This is the CDP-based procedure from `../vacuumtube-vaapi/README.md`, pointed
at the forked app ID.  Put a VP9 file and an autoplaying muted HTML page in
`/tmp/quartz64-testmedia`; the page should contain an element such as:

```html
<video src="test-vp9.webm" autoplay muted></video>
```

Start the app with the test directory exposed and Chromium's remote debugging
port enabled:

```sh
flatpak run --filesystem=/tmp/quartz64-testmedia:ro \
  --command=startvacuumtube dev.jannik.VacuumTubeV4L2 \
  --remote-debugging-port=9222
```

Navigate the page through `http://127.0.0.1:9222/json/list` to
`file:///tmp/quartz64-testmedia/test.html`, then run:

```sh
./scripts/check-vacuumtube-hw.sh
```

This requires `curl` and a WebSocket client such as `websocat`.  It verifies
the same media pipeline that YouTube Leanback uses once a video starts, without
needing an account.

## Updating to a new VacuumTube release

This is the cost of the fork.  Every upstream VacuumTube release needs a manual
rebuild and re-bundle:

1. Clone `flathub/rocks.shy.VacuumTube` and check out the commit for the new
   release.
2. Copy its `rocks.shy.VacuumTube.yml` and regenerate/copy its
   `flatpak-sources.json` (the upstream file is produced with
   `flatpak-node-generator`).
3. Re-apply only the intended drift listed above: app ID, personal
   metadata/icon, driver module, `LIBVA_*` finish-args, and the metadata
   install lines.
4. Diff the result against upstream and confirm nothing upstream was dropped.
5. Rebuild, reinstall, and rerun the verification above.

The driver commit and patches only need attention when the runtime/libva ABI
changes, not for every app release.

## Limitations

- **VP9 Profile 0 (8-bit) only.**  H.264, HEVC, AV1 and 10-bit VP9 are not
  hardware-decoded by this driver fork.
- **Wayland only.**  Chromium's GL zero-copy NV12 import is not usable on X11
  in this stack.
- **4K is memory-bound** on the 256 MB CMA reservation; 1080p is the verified
  target.
- **Runtime updates can break the bundled driver.**  A `flatpak update` of
  `org.freedesktop.Platform//25.08` can change libva.  Rebuild and reinstall
  the whole fork if hardware decoding stops working.
- **No Flathub updates.**  The fork does not auto-update like the official
  Flathub app.

More detail on the driver, codec limits and fallbacks is in
`../vacuumtube-vaapi/README.md`.

## Rollback

```sh
flatpak uninstall --user dev.jannik.VacuumTubeV4L2
```

This removes only the forked app and its runtime dependencies.  It does not
touch the official `rocks.shy.VacuumTube`, the Jellyfin Flatpak, the kernel,
DTBs, modules, or bootloader.  To remove the fork's saved settings as well:

```sh
rm -rf ~/.var/app/dev.jannik.VacuumTubeV4L2
```

## Files

```text
vacuumtube-flatpak/README.md
vacuumtube-flatpak/dev.jannik.VacuumTubeV4L2.yml
vacuumtube-flatpak/flatpak-sources.json
vacuumtube-flatpak/startvacuumtube
vacuumtube-flatpak/dev.jannik.VacuumTubeV4L2.desktop
vacuumtube-flatpak/dev.jannik.VacuumTubeV4L2.metainfo.xml
vacuumtube-flatpak/init_compat.c
vacuumtube-flatpak/env.sh
vacuumtube-flatpak/configs/flags.txt
vacuumtube-flatpak/patches/0001-libva-v4l2-request-autodetect-rkvdec.patch
vacuumtube-flatpak/patches/0002-libva-v4l2-request-vp9-profile0-only.patch
vacuumtube-flatpak/patches/0003-libva-v4l2-request-reduce-frame-pool.patch
vacuumtube-flatpak/patches/0004-libva-v4l2-request-bind-on-export.patch
vacuumtube-flatpak/patches/0005-libva-v4l2-request-export-separate-layers.patch
vacuumtube-flatpak/patches/0006-libva-v4l2-request-build-init-compat.patch
vacuumtube-flatpak/scripts/build-flatpak.sh
vacuumtube-flatpak/scripts/configure-vacuumtube.sh
vacuumtube-flatpak/scripts/check-vacuumtube-hw.sh
```

## License and credit

VacuumTube is MIT-licensed; the upstream license text is kept in `LICENSE`.
The `libva-v4l2-request` fork is MIT/LGPL-2.1-or-later as described by its
`COPYING` files.  This directory is a personal packaging recipe, not an official
VacuumTube distribution.  See `../LICENSE-NOTES.md`.
