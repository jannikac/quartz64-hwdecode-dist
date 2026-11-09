# VacuumTube hardware decode on Quartz64-B

This directory adds hardware decode to the **official, Flathub-distributed**
VacuumTube YouTube client on the Pine64 Quartz64 Model B (RK3566).  It does not
fork, rebuild, or repackage VacuumTube.  It builds a forked VA-API driver
(`libva-v4l2-request`, VP9-enabled) and installs it as a user Flatpak override
pointed only at `rocks.shy.VacuumTube`.

This is the host-side script/patch set, not a Flatpak.  There is no manifest
here: the app under `/app` stays the signed upstream build, while the driver
lives in `~/.local/lib/v4l2-request-<runtime>` and is exposed read-only through
`flatpak override`.

The short version: **VacuumTube is an Electron app, not a GStreamer or mpv
app.**  It cannot use the working `v4l2sl*` GStreamer decoders or the patched
`/opt/mpv-v4l2` stack from the board bring-up repository.  Its Chromium engine
only has the VA-API hardware-decode backend compiled in.  This directory adds a
VA-API driver on top of the same V4L2 Request stateless kernel interface that
GStreamer and FFmpeg already use.

## What was verified about the app

Pinned source: VacuumTube `v2.0.1`, Electron `44.5.1`, Chromium
`152.0.7977.130`.

- VacuumTube is packaged as an Electron app (`package.json` uses
  `electron`/`electron-builder`; Linux is shipped as a Flatpak using
  `org.electronjs.Electron2.BaseApp`).
- Its playback path is the YouTube Leanback HTML5 player inside Chromium.  The
  app's ad blocker, controller support, codec filter and settings are
  preload/JavaScript modules; none of them replace the media engine.
- The aarch64 Electron 44.5.1 binary contains `VaapiVideoDecoder`,
  `VP9VaapiVideoDecoderDelegate` and the `AcceleratedVideoDecodeLinuxGL`
  feature.  It does not contain a stateless V4L2 decode backend.
  Chromium's `use_v4l2_codec` build option is false in Electron, so the
  `V4L2VideoDecoder` path used by ChromeOS and by the RK3588 Chromium guide is
  not present.
- VacuumTube already enables these Chromium features when its **Hardware
  Decoding** setting is on:

  ```text
  AcceleratedVideoEncoder
  AcceleratedVideoDecoder
  AcceleratedVideoDecodeLinuxGL
  AcceleratedVideoDecodeLinuxZeroCopyGL
  ```

  That selects the VA-API platform decoder on Linux.  The missing piece is a
  VA-API driver that speaks to `rkvdec`.

## Why GStreamer/mpv cannot be used directly

| Component | Media API | Uses rkvdec? |
|---|---|---|
| GStreamer `v4l2slvp9dec` | V4L2 stateless Request API | yes |
| `/opt/mpv-v4l2` (patched FFmpeg) | `v4l2request` hwaccel | yes |
| Chromium inside VacuumTube | VA-API | only with a VA-API driver |

The preload scripts have no supported way to hand the video element to an
external mpv process.  Forcing the stream codec is the only supported knob, so
the in-app path has to be VA-API.

## Approach

1. Build a VA-API driver for `rkvdec` (`libva-v4l2-request`) with working VP9
   Profile 0.
2. Install it for the glibc Flatpak runtime used by VacuumTube, not for the
   musl host.  Flatpak apps cannot load host musl libraries.
3. Point only `rocks.shy.VacuumTube` at the driver with a user Flatpak
   override.
4. Force the app onto Wayland and restrict YouTube to VP9 Profile 0.

The driver is [dongioia/libva-v4l2-request] `rk3588-vp9`, pinned to commit
`ed4bc90a8c979c83790013297850960c73a3d2f1`.  Bootlin's upstream driver only
implements MPEG-2/H.264/HEVC with an obsolete control interface and never
supported VP9.  The fork adds the VP9 stateless backend used by the RK3588
`rkvdec2` work; the same V4L2 controls are implemented by the RK3566
`vdpu346` backend in this repository's 7.3 kernel.

Five local patches are applied:

| Patch | Purpose |
|---|---|
| `0001-libva-v4l2-request-autodetect-rkvdec.patch` | Find `/dev/videoN` and `/dev/mediaN` by the `rkvdec` name instead of assuming `video0`/`media0`.  Device numbers are not stable and differ inside the Flatpak sandbox. |
| `0002-libva-v4l2-request-vp9-profile0-only.patch` | Advertise only VP9 Profile 0.  H.264/HEVC/MPEG-2 are stubs in this fork, and VP9 Profile 2 (10-bit) produces NV15, which Chromium cannot import. |
| `0003-libva-v4l2-request-reduce-frame-pool.patch` | Reduce the preallocated V4L2 capture pool from 64 to 32 buffers.  Chromium asks for up to 25 VP9 output frames; 64 4K NV12 buffers would exceed the board's 256 MB CMA reservation. |
| `0004-libva-v4l2-request-bind-on-export.patch` | Bind a CAPTURE buffer when Chromium exports a new VA surface.  Chromium exports the whole frame pool before the first decode; the upstream fork deliberately failed that export, which would make Chromium fall back to software. |
| `0005-libva-v4l2-request-export-separate-layers.patch` | Honour `VA_EXPORT_SURFACE_SEPARATE_LAYERS` by exporting one plane per layer. Chromium assumes one plane per layer and otherwise builds a broken single-plane NV12 pixmap. |

## Requirements

- The board is running the 7.3 kernel with a bound `rkvdec` and working
  GStreamer VP9 decode.  Build and deploy it with `../kernel-patches-dist/`.
- VacuumTube is installed from Flathub.
- The graphical session is Wayland.  Chromium's GL zero-copy NV12 import on
  X11 is not usable; the app must run under Wayland.
- A build host with an aarch64 glibc cross compiler for the driver (the
  `build-libva-cross.sh` path).  Alternatively, about 2 GB free on the board
  for the `org.freedesktop.Sdk`.  This board only had about 1 GB, so the
  cross build was used.
- `jq` installed on the board before running `configure-vacuumtube.sh`.
  Without it the script does not modify `config.json`; it only prints the
  settings to change by hand, which is easy to miss.

## Step 1: prove the VA-API driver on the host (optional, legacy `/opt` stack)

This uses the old musl FFmpeg/mpv `/opt` stack from the original bring-up.  On
a clean repo-only board that stack does not exist, so skip to Step 2 and use
the local VP9 test under Verification instead.

```sh
sudo apk add build-base meson linux-headers libva-dev libdrm-dev libva-utils

cd vacuumtube-vaapi
./scripts/build-libva-host.sh
sudo mkdir -p /opt/libva-v4l2-request
sudo cp -a ~/.cache/vacuumtube-hwdecode/root-host/opt/libva-v4l2-request \
   /opt/
```

Check the profiles:

```sh
LIBVA_DRIVER_NAME=v4l2_request \
LIBVA_DRIVERS_PATH=/opt/libva-v4l2-request/lib/dri \
vainfo --display drm --device /dev/dri/renderD128
```

Expected, and only this profile:

```text
VAProfileVP9Profile0            : VAEntrypointVLD
```

Decode a real file with VA-API (CPU readback, so it is a strict correctness
test rather than a zero-copy test):

```sh
./scripts/test-vaapi-host.sh /opt/libva-v4l2-request \
  /home/<user>/test-claude/test.vp9.webm
```

Expected: `Using hardware decoding (vaapi-copy)`.  If this fails, do not
continue to the Flatpak step; check `/tmp/vaapi-mpv.log` and the kernel log.

## Step 2: build the glibc driver and install the Flatpak override

The Flatpak SDK is about 1.7 GB installed, and this board only had about 1 GB
free.  The primary path is therefore to cross-build the driver on the NixOS
build host with an aarch64 glibc toolchain and copy only the `.so` to the
board.  The driver has no dependency other than `libc.so.6`; libva loads it
through its driver vtable.

On a stock board, install the development headers first, then export them:

```sh
sudo apk add libva-dev libdrm-dev linux-headers

tar -C /usr/include -cf /tmp/vacuumtube-headers.tar \
  va linux asm asm-generic libdrm
```

Copy that tarball to the build host and unpack it:

```sh
mkdir -p ~/vacuumtube-headers
tar -C ~/vacuumtube-headers -xf vacuumtube-headers.tar
```

On the build host (from the repository root):

```sh
nix-shell -p pkgsCross.aarch64-multiplatform.stdenv.cc --run \
  'CROSS_CC=aarch64-unknown-linux-gnu-gcc \
   HEADERS=$HOME/vacuumtube-headers \
   ./vacuumtube-vaapi/scripts/build-libva-cross.sh /tmp/vacuumtube-driver'
```

The script applies all five patches, forces the driver to report VA-API 1.22
(the runtime's libva), and exports `__vaDriverInit_1_22` plus wrappers for
1.23/1.24/1.25.  It prints the copy/install commands.  On this board the
relevant install is:

```sh
scp /tmp/vacuumtube-driver/v4l2_request_drv_video.so user@board:/tmp/

ssh user@board '
  cd /path/to/quartz64-hwdecode-dist
  ./vacuumtube-vaapi/scripts/install-driver-override.sh \
    /tmp/v4l2_request_drv_video.so'
```

`install-driver-override.sh` detects the runtime branch from
`flatpak info rocks.shy.VacuumTube`, installs the driver under
`~/.local/lib/v4l2-request-<version>/lib/dri`, and applies the read-only
filesystem plus `LIBVA_*` overrides only to `rocks.shy.VacuumTube`.

No system files, the runtime or the application installation are modified.

If the board has enough free space for the SDK, `scripts/build-libva-flatpak.sh`
performs the same build natively inside the matching
`org.freedesktop.Sdk//<version>` and applies the override itself.  Do not use
it on a full root filesystem.

## Step 3: configure VacuumTube

```sh
./scripts/configure-vacuumtube.sh
```

This writes `~/.var/app/rocks.shy.VacuumTube/config/VacuumTube/flags.txt`:

```text
--ozone-platform-hint=auto
--ignore-gpu-blocklist
--enable-gpu-rasterization
--enable-zero-copy
--enable-features=VaapiIgnoreDriverChecks,VaapiVideoDecoder
```

and enables these settings in `config.json`:

| Setting | Value | Why |
|---|---|---|
| `hardware_decoding` | `true` | runs Chromium's VA-API feature set |
| `h264ify` | `true` | enables the per-codec filter |
| `h264ify_disable_webm` | `false` | VP9 is normally in WebM; do not block the container |
| `h264ify_disable_vp8` | `true` | VP8 is not needed |
| `h264ify_disable_vp9` | `false` | keep VP9, the only hardware codec |
| `h264ify_disable_av1` | `true` | AV1 is not supported by rkvdec on this board |

Existing user settings are backed up and merged with `jq`; without `jq` the
script prints the settings to change in the UI instead of overwriting them.

Start VacuumTube normally from its desktop entry.

## Verification

Play a video, then run:

```sh
./scripts/check-vacuumtube-hw.sh
```

The script reports the Flatpak overrides, the processes that mapped the driver,
open `/dev/video*` / `/dev/media*` descriptors and the rkvdec interrupt delta
over five seconds.  It deliberately does not query titles, paths or URLs.

Expected while a VP9 video is playing:

- `v4l2_request_drv_video.so` is mapped by a Chromium GPU process;
- one process holds the `rkvdec` video node and its media node;
- the rkvdec IRQ counter increases;
- CPU use is well below software decode.

Depending on the DTB, the decoder interrupt is named `rkvdec` or
`fdf80200.video-codec`; the check script accepts both.

### Local VP9 test without a YouTube login

For a repeatable test, serve a local VP9 file from a small HTML page and drive
the Chromium session with its remote debugging port.  With the test media in
`/tmp/quartz64-testmedia`:

```sh
flatpak run --filesystem=/tmp/quartz64-testmedia:ro \
  --command=startvacuumtube rocks.shy.VacuumTube --remote-debugging-port=9222
```

Then navigate the page to `file:///tmp/quartz64-testmedia/test.html` through
`http://127.0.0.1:9222/json/list` and run `check-vacuumtube-hw.sh`.  This
requires `curl` and a WebSocket client such as `websocat`; both are available
as Alpine packages.  The HTML page should contain an autoplaying muted
`<video src="test-vp9.webm">` element.

### Measured on this board

The same Electron 44.5.1 / Chromium 152 binary from the VacuumTube Flatpak was
run with a local 1080p VP9 file to avoid requiring a YouTube account during
bring-up.  The test app was executed through the real `startvacuumtube` /
zypak / Flatpak sandbox, not just as an unsandboxed binary:

```text
GPU process fds:   /dev/video3 (rkvdec), /dev/media2
driver mapped:     ~/.local/lib/v4l2-request-25.08/lib/dri/v4l2_request_drv_video.so
rkvdec IRQ delta:  ~120 interrupts over 5 s while video was playing
video:             1920x1080 VP9, frames advancing, no decoder reset
```

YouTube playback itself still requires the account owner to sign in; the media
pipeline above is the same one Leanback uses once a video starts.  Live
YouTube playback in VacuumTube was also checked on this board: the GPU process
mapped the driver, held `/dev/video3` and `/dev/media2`, and the rkvdec IRQ
counter advanced by about 141 over 5 s.

For the Chromium view, open the GPU diagnostics page:

```sh
flatpak run --command=startvacuumtube rocks.shy.VacuumTube --debug-gpu
```

Expected:

```text
Video Decode: Hardware accelerated
```

The video decoder name in `chrome://media-internals` should be
`VaapiVideoDecoder`, not `VpxVideoDecoder`/`FFmpegVideoDecoder`.

## Limitations

- **VP9 Profile 0 (8-bit) only.**  This is the codec YouTube serves to the
  spoofed Cobalt client once AV1/VP8 are filtered out.  H.264, HEVC, AV1 and
  10-bit VP9 fall back to software or are blocked.  This is a driver-fork
  limitation, not a kernel limitation: GStreamer and mpv still decode H.264,
  HEVC and 10-bit content through `v4l2request`.
- **Wayland only.**  GLX cannot import NV12/P010 dmabufs.  The flag written by
  `configure-vacuumtube.sh` selects Wayland when the session provides it.
- **Runtime updates break the driver.**  A `flatpak update` of
  `org.freedesktop.Platform` can change the libva ABI.  Rebuild and reinstall
  with `build-libva-cross.sh` (or `build-libva-flatpak.sh` if the SDK is
  installed) after updating the runtime.  If the runtime moves beyond VA-API
  1.25, add the new init wrapper to `init_compat.c`.
- **The driver is an out-of-tree fork.**  It is pinned by commit because it is
  not upstream and the VP9 compressed-header handling is board-specific.
  Treat it like the other local `/opt` packages: do not blindly update it.
- **10-bit output is NV15.**  The rkvdec VDPU346 backend captures 10-bit as
  NV15, which neither Mesa nor Chromium can import in this stack.  Profile 2
  is therefore not advertised to Chromium.
- **4K is memory-bound.**  Chromium asks for 25 VP9 output frames.  At 4K,
  25 NV12 buffers are about 310 MB, above the board's 256 MB CMA reservation.
  1080p is the verified target; 4K needs a larger `cma=` boot parameter or a
  smaller frame pool.
- **Chromium sandbox.**  If the GPU process cannot load a `.so` from
  `$HOME` under the Flatpak bubblewrap sandbox, the fallback is
  `--no-sandbox` in `flags.txt`.  Prefer finding a narrower permission first;
  `--no-sandbox` reduces the isolation of the app.

## Fallback: hand playback to mpv

If the VA-API path fails on a future Mesa/Chromium update, the known-working
hardware path remains the patched mpv stack.  YouTube Leanback does not expose
a supported external-player hook, so this is a manual/URL-level fallback (for
example `yt-dlp` plus `/opt/mpv-v4l2/bin/mpv --hwdec=v4l2request`), not an
in-app setting.  It is documented here only so a broken VA-API stack does not
leave the board without any hardware YouTube option.

## Troubleshooting

### `vainfo` shows no VP9 profile

Run `vainfo` with the driver environment explicitly set and check that the
`rkvdec` node is present:

```sh
ls /sys/class/video4linux/*/name
cat /sys/class/video4linux/video*/name
```

The auto-detection patch searches `/dev/video0..63` for the name `rkvdec` and
`/dev/media0..63` for a media device with model/driver `rkvdec`.  If the board
has a vendor MPP node instead, the mainline `rkvdec` driver is not bound; fix
the kernel first (`DRIVER.md`, `BRINGUP.md`).

### Driver builds but Electron does not map it

Check the overrides:

```sh
flatpak override --user --show rocks.shy.VacuumTube
```

They must contain both `LIBVA_DRIVER_NAME=v4l2_request` and
`LIBVA_DRIVERS_PATH=$HOME/.local/lib/v4l2-request-<version>/lib/dri`, and the
driver file must be readable by the user.  Then confirm the app is running
under Wayland:

```sh
flatpak run --command=sh rocks.shy.VacuumTube -c 'echo $XDG_SESSION_TYPE $WAYLAND_DISPLAY'
```

### Runtime update

If `flatpak update` replaced `org.freedesktop.Platform`, the old driver may no
longer match the runtime's libva symbol.  Rebuild with the cross toolchain
(`scripts/build-libva-cross.sh`) or, if the SDK fits, with
`scripts/build-libva-flatpak.sh`, then reinstall the driver and rerun the
`flatpak override`.

### Kernel headers are too old

The SDK normally ships recent UAPI headers.  If `meson` rejects the V4L2
Request API, export the pinned kernel headers and pass them explicitly:

```sh
make -C ../../linux headers_install INSTALL_HDR_PATH="$PWD/.uapi"
KERNEL_HEADERS="$PWD/.uapi" ./scripts/build-libva-flatpak.sh
```

The script copies the tree into the build directory so it is visible inside
the SDK sandbox.

### Blue/green picture or no picture

That is the NV12 dmabuf import path failing on Mesa/Panfrost, the same class of
problem documented for 10-bit NV15 in the board bring-up repository's
`HWDECODE.md`.  First confirm the driver
works with `test-vaapi-host.sh`.  If VA-API copy works but Chromium zero-copy
does not, use the mpv fallback; do not try to fix it by changing Jellyfin or
VacuumTube settings.

### App falls back to software after an update

Check `chrome://gpu` with `--debug-gpu`.  If `Video Decode` says software, the
Chromium feature set is not active.  Verify `flags.txt`, then restart the app.
If the feature list was overridden by a newer VacuumTube version, reapply
`configure-vacuumtube.sh`.

## Rollback

```sh
./scripts/uninstall-vacuumtube-v4l2.sh
```

That removes the driver, the `LIBVA_*` overrides and the read-only filesystem
mount, and leaves VacuumTube and its settings installed.  The host test
driver under `/opt/libva-v4l2-request`, if installed, is independent:

```sh
sudo rm -rf /opt/libva-v4l2-request
```

## Files

```text
vacuumtube-vaapi/README.md
vacuumtube-vaapi/env.sh
vacuumtube-vaapi/configs/flags.txt
vacuumtube-vaapi/patches/0001-libva-v4l2-request-autodetect-rkvdec.patch
vacuumtube-vaapi/patches/0002-libva-v4l2-request-vp9-profile0-only.patch
vacuumtube-vaapi/patches/0003-libva-v4l2-request-reduce-frame-pool.patch
vacuumtube-vaapi/patches/0004-libva-v4l2-request-bind-on-export.patch
vacuumtube-vaapi/patches/0005-libva-v4l2-request-export-separate-layers.patch
vacuumtube-vaapi/init_compat.c
vacuumtube-vaapi/scripts/install-driver-override.sh
vacuumtube-vaapi/scripts/build-libva-host.sh
vacuumtube-vaapi/scripts/build-libva-cross.sh
vacuumtube-vaapi/scripts/build-libva-flatpak.sh
vacuumtube-vaapi/scripts/configure-vacuumtube.sh
vacuumtube-vaapi/scripts/check-vacuumtube-hw.sh
vacuumtube-vaapi/scripts/test-vaapi-host.sh
vacuumtube-vaapi/scripts/uninstall-vacuumtube-v4l2.sh
```

[dongioia/libva-v4l2-request]: https://github.com/dongioia/libva-v4l2-request
