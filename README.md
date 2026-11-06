# Quartz64-B userland hardware-decode distribution

Packaging for the userland half of a working hardware-video-decode bring-up on
the Pine64 Quartz64 Model B (RK3566, mainline `rkvdec` / VDPU346).  The board
runs postmarketOS v26.06 with the `chewitt/linux` `rockchip-7.3.y` kernel
(`7.3.0-quartz64-vp9+`).

This repository splits the previously working setup into independently
consumable pieces.  It is a **personal/sideloaded** effort, not a Flathub
submission.

The original board bring-up repository, with the kernel patches, DTBs, device
tree sources, driver notes, and the working Alpine/musl APK build, is:

```
/home/jannik/Development/quartz64-b-hvec-vp9-decoder-deepseek
```

That repository is source material ("SRC").  This repository only reads from
it; it does not modify it.

## Contents

| Directory | What it is |
|---|---|
| `jellyfin-flatpak/` | A Flatpak of Jellyfin Desktop (JMP) 2.0.0 with patched FFmpeg 8.1.1 and mpv 0.41.0 using the V4L2 Request stateless hwaccel (`v4l2request`). Personal app ID `dev.jannik.JellyfinDesktopV4L2`. |
| `vacuumtube-vaapi/` | **Not** a Flatpak.  A host-run script/patch set that builds the forked `libva-v4l2-request` VA-API driver (VP9 Profile 0) and installs it as a user Flatpak override pointed only at the official Flathub `rocks.shy.VacuumTube`.  VacuumTube itself is not forked or rebuilt. |
| `vacuumtube-flatpak/` | A personal forked Flatpak of VacuumTube 2.0.1 (`dev.jannik.VacuumTubeV4L2`) with the same VA-API driver built in as a module and `LIBVA_*` baked into `finish-args`.  No post-install driver override; every upstream VacuumTube release needs a manual rebuild and re-bundle. |
| `kernel-patches-dist/` | Builds and deploys the pinned `7.3.0-quartz64-vp9+` kernel (`chewitt/linux` + two rkvdec patches), including the initramfs module swap and a confirmation-driven boot-partition deployment with a `.stock` rollback copy. |

### Why the split

- JMP's hardware decode needs mpv/FFmpeg with the `v4l2request` hwaccel.
  The Flatpak therefore builds its own FFmpeg and mpv under `/app`.
- Moving from Alpine/musl to a glibc Flatpak changes the old single-FFmpeg
  constraint.  Milestone 1 in `jellyfin-flatpak/README.md` records the actual
  finding: the KDE/base-app Qt WebEngine has no dynamic `libav*` dependency, so
  the Alpine parity patch is not needed here.  This was measured, not assumed.
- VacuumTube is Electron/Chromium, not mpv/GStreamer.  It can only use a VA-API
  driver.  Two approaches are kept side by side:
  `vacuumtube-vaapi/` leaves the official Flathub app in place and points a
  per-app override at a separately built driver; `vacuumtube-flatpak/` forks
  the Flathub manifest under a personal app ID and bakes the driver and
  environment into the app.  Neither replaces the other, and neither is a
  Flathub submission.
- `--device=all` is accepted for the JMP Flatpak and the VacuumTube fork
  because the V4L2 media controller has no Flatpak portal.  This is one reason
  these builds are explicitly not for Flathub.

### VacuumTube: choose one of two options

Both options use the same pinned `libva-v4l2-request` driver and have the same
VP9 Profile 0 codec limits.  The difference is packaging and maintenance:

| | `vacuumtube-vaapi/` | `vacuumtube-flatpak/` |
|---|---|---|
| VacuumTube build | Official Flathub app, untouched | Personal fork `dev.jannik.VacuumTubeV4L2` |
| Driver | User override, separate `.so` | Built into `/app/lib/dri` |
| Install | Install app, then run two scripts | Install one bundle (plus app settings) |
| App updates | Automatic from Flathub | **Manual rebuild/re-bundle per upstream release** |
| Runtime/ABI update | Rebuild only the small driver | Rebuild the whole Electron app and driver |
| Best for | Normal day-to-day use, least maintenance | One self-contained artifact, no override scripts |

The fork gives up automatic Flathub updates: every upstream VacuumTube release
now requires manually rebuilding and re-bundling the whole thing.  The official
app plus override only needs the small driver rebuilt when a runtime update
changes the libva ABI.  Choose `vacuumtube-vaapi/` unless the single bundled
artifact is specifically what you want.

## End-user guide (install and use)

This is for someone with a Quartz64-B that already boots the working 7.3
kernel and wants hardware-decoded Jellyfin plus hardware-decoded VacuumTube via
one of the two options above.  You do **not** need to build anything if you
already have these files from the repo owner:

```text
dev.jannik.JellyfinDesktopV4L2.flatpak
v4l2_request_drv_video.so

# Only if you chose the forked VacuumTube option:
dev.jannik.VacuumTubeV4L2.flatpak
```

If you do not have them, use the build/development quick start below, or ask
the repo owner for the matching bundle and driver.

### Before you start

- The board must be running the `7.3.0-quartz64-vp9+` kernel with a bound
  `rkvdec` device.  If it is not, build and deploy it with the separate,
  manual procedure in `kernel-patches-dist/`.
- Use a Wayland session.  Chromium's zero-copy video import does not work on
  X11 in this stack.
- Have Flathub configured.  If you choose the official-app option, also
  install the official VacuumTube app:

  ```sh
  flatpak remote-add --if-not-exists --user flathub \
    https://flathub.org/repo/flathub.flatpakrepo
  flatpak install --user flathub rocks.shy.VacuumTube
  ```

  The forked option installs its own bundle below and does not modify the
  official app.

- Use your own Jellyfin account.  This repository never ships credentials,
  tokens, or server URLs.

### 1. Install Jellyfin Desktop (hardware-decoded)

Copy the bundle to the board, then install and start it:

```sh
flatpak install --user --noninteractive \
  /path/to/dev.jannik.JellyfinDesktopV4L2.flatpak

flatpak run dev.jannik.JellyfinDesktopV4L2
```

In the app:

1. Log in to your own Jellyfin server.
2. Open **Client Settings** and enable **Hardware Decoding**.
3. Play a video.  The native mpv player should be selected automatically.

This app is a personal build (`dev.jannik.JellyfinDesktopV4L2`), not the
official `org.jellyfin.JellyfinDesktop` Flathub app, and is not affiliated with
the Jellyfin project.

To check that hardware decode is active while a video plays:

```sh
cd /path/to/quartz64-hwdecode-dist
jellyfin-flatpak/scripts/check_jmp_hw.sh
```

Expected: `hwdec-current = v4l2request`, no host/system FFmpeg in the player's
process maps, and a rising `rkvdec` IRQ count.  The script does not read media
titles, paths, or stream URLs.

### 2. Install VacuumTube with hardware decode (choose one)

Both options use the same driver and have the same VP9 Profile 0 limits.  Pick
one; they can coexist.

**Option A: official Flathub app plus driver override (recommended for normal
use).**  VacuumTube itself stays the normal Flathub build.  Copy the driver to
the board and run the installer:

```sh
cd /path/to/quartz64-hwdecode-dist

./vacuumtube-vaapi/scripts/install-driver-override.sh \
  /path/to/v4l2_request_drv_video.so

./vacuumtube-vaapi/scripts/configure-vacuumtube.sh
```

Then start VacuumTube normally from its desktop entry.  The override applies
only to `rocks.shy.VacuumTube`; other Flatpak apps are unaffected.  This option
keeps Flathub automatic updates.

To check hardware decode while a VP9 video plays:

```sh
./vacuumtube-vaapi/scripts/check-vacuumtube-hw.sh
```

**Option B: personal forked Flatpak with the driver bundled.**  Copy the bundle
to the board, install it, and write the app's own flags/settings:

```sh
flatpak install --user --noninteractive \
  /path/to/dev.jannik.VacuumTubeV4L2.flatpak

cd /path/to/quartz64-hwdecode-dist
./vacuumtube-flatpak/scripts/configure-vacuumtube.sh

flatpak run dev.jannik.VacuumTubeV4L2
```

The driver and `LIBVA_*` environment are already inside the app, so there is no
`flatpak override` step.  This option does **not** auto-update; see
`vacuumtube-flatpak/README.md` for the manual rebuild/re-bundle procedure.

To check hardware decode while a VP9 video plays:

```sh
./vacuumtube-flatpak/scripts/check-vacuumtube-hw.sh
```

For both options, expected: the driver is mapped by a Chromium GPU process, the
`rkvdec` `/dev/video*` and `/dev/media*` nodes are open, and the `rkvdec` IRQ
counter increases.  In Chromium's `chrome://gpu`, video decode should say
hardware accelerated.

### What works and what does not

- Jellyfin: 8-bit H.264, HEVC, and VP9, including 4K, use `v4l2request`.
  10-bit HEVC currently captures NV15, which the compositor cannot import, so
  it may show blue or fall back to software.
- VacuumTube (either option): only VP9 Profile 0 (8-bit) is supported by this
  driver fork.  H.264, HEVC, AV1, and 10-bit VP9 are not hardware-decoded.
- AV1 is not hardware-decoded on the RK3566 in either app.
- A Flatpak runtime update can change the libva ABI.  For the official-app
  option, rebuild/reinstall the small driver after a `flatpak update`.  For the
  forked option, rebuild and reinstall the whole bundle.

### Rollback

```sh
# Jellyfin Desktop personal build
flatpak uninstall --user dev.jannik.JellyfinDesktopV4L2

# VacuumTube forked Flatpak (if you chose Option B)
flatpak uninstall --user dev.jannik.VacuumTubeV4L2

# VacuumTube driver/override only (leaves the official app installed)
cd /path/to/quartz64-hwdecode-dist
./vacuumtube-vaapi/scripts/uninstall-vacuumtube-v4l2.sh
```

None of these rollbacks touches the kernel, DTBs, modules, bootloader, or the
official Flathub apps.

## Build and development quick start

### 0. Cross-compile and test the hardware path (no board build)

Use the ephemeral Nix shell and the cross FFmpeg build to verify `rkvdec`
without compiling anything on the Quartz64:

```sh
nix-shell
./jellyfin-flatpak/cross-build-ffmpeg.sh
```

Then copy `cross-build/cross-ffmpeg-aarch64.tar.gz` and
`jellyfin-flatpak/scripts/test-cross-ffmpeg.sh` to the board and run the test.
Details are in `jellyfin-flatpak/README.md`.  This path was used to verify the
cross-built FFmpeg on the board: it reported
`Using V4L2 media driver rkvdec-core (7.3.0)` and the `rkvdec` IRQ counter
advanced during decode.

### 1. Jellyfin Desktop Flatpak

On this x86_64 host the build stays manifest-driven: `flatpak-builder` runs
inside an unprivileged user namespace with a sandboxed `binfmt_misc` entry for
qemu-aarch64, so no host binfmt configuration is needed.  The script downloads
the aarch64 SDK/base runtimes and builds the whole app, then copy only the
bundle to the board:

```sh
nix-shell
./jellyfin-flatpak/build-flatpak.sh
scp jellyfin-flatpak/dist/dev.jannik.JellyfinDesktopV4L2.flatpak \
  jannik@192.168.1.130:/tmp/
```

On a native aarch64 host the same script is a plain native flatpak-builder
build.

On the board:

```sh
flatpak install --user --noninteractive \
  /tmp/dev.jannik.JellyfinDesktopV4L2.flatpak
flatpak run dev.jannik.JellyfinDesktopV4L2
```

See `jellyfin-flatpak/README.md` for pins, patch rationale, Milestone 1, and
verification details.

### 2. VacuumTube VA-API driver (official-app option)

VacuumTube stays the official Flathub build.  Build the driver on a host with
an aarch64 glibc cross compiler, then install it on the board:

```sh
scp /tmp/vacuumtube-driver/v4l2_request_drv_video.so \
  jannik@192.168.1.130:/tmp/

ssh jannik@192.168.1.130 '
  cd /path/to/quartz64-hwdecode-dist
  ./vacuumtube-vaapi/scripts/install-driver-override.sh \
    /tmp/v4l2_request_drv_video.so
  ./vacuumtube-vaapi/scripts/configure-vacuumtube.sh
'
```

See `vacuumtube-vaapi/README.md` for the full build and verification flow.

### 3. VacuumTube fork Flatpak (bundled-driver option)

This builds the whole forked Electron app with the driver as a manifest module.
It needs an aarch64 host, or x86_64 with aarch64 binfmt/qemu-user; it does not
use the Jellyfin cross-toolchain path.

```sh
cd /path/to/quartz64-hwdecode-dist/vacuumtube-flatpak
./scripts/build-flatpak.sh
# ARCH=aarch64 ./scripts/build-flatpak.sh  # on a prepared x86_64 host

scp dist/dev.jannik.VacuumTubeV4L2.flatpak \
  jannik@192.168.1.130:/tmp/

ssh jannik@192.168.1.130 '
  flatpak install --user --noninteractive /tmp/dev.jannik.VacuumTubeV4L2.flatpak
'
```

See `vacuumtube-flatpak/README.md` for pins, fork drift, the libva ABI check,
verification, and the manual update procedure.

## Automated verification

`verify-userland.sh` is the end-to-end board verification script.  It:

1. Logs the current state to `preflight-state.log` (read-only).
2. Uninstalls the old Alpine `ffmpeg-v4l2`, `mpv-v4l2`, and `jellyfin-desktop`
   APKs, plus the old desktop entries/wrappers.  It does **not** delete
   `/home/jannik/hwdecode-packages/*.apk`.
3. Removes the existing VacuumTube VA-API override/driver and
   `/opt/libva-v4l2-request` if present.
4. Confirms the board is clean.
5. Installs this repository's Jellyfin Flatpak bundle and the VacuumTube driver
   + override.
6. Runs hardware checks for both apps: player hwdec state, process maps,
   and the `rkvdec` IRQ counter.  It reports pass/fail per app.

`verify-userland.sh` covers the Jellyfin build and the official-app VacuumTube
override path.  It does not install the forked VacuumTube Flatpak; use
`vacuumtube-flatpak/scripts/check-vacuumtube-hw.sh` for that option.

Usage:

```sh
# The script uses ordinary key-based SSH; it never stores a password.
BOARD=jannik@192.168.1.130 ./verify-userland.sh --yes

# If your artifacts are not in the default locations:
JELLYFIN_FLATPAK_BUNDLE=/path/to/dev.jannik.JellyfinDesktopV4L2.flatpak \
VA_DRIVER_SO=/path/to/v4l2_request_drv_video.so \
BOARD=jannik@192.168.1.130 ./verify-userland.sh --yes
```

Destructive step: read `jellyfin-flatpak/README.md` and the script header
before running it.  The uninstall phase changes the board's installed userland.

The board's existing state at the time this repository was created is recorded
in `preflight-state.log`.

## Security and privacy

- Never commit or publish Jellyfin credentials, `cred.json`, API tokens,
  server URLs containing keys, or playback logs containing stream URLs.
- The verification code reads only codec/hwdec/player state and process maps.
  It does not query `media-title`, file paths, or stream URLs.
- The VacuumTube scripts only read process maps, open `/dev/video*`/
  `/dev/media*` descriptors, and `/proc/interrupts`.
- Do not put passwords in this repository or in committed scripts.  Use the
  board's existing SSH keys/agent.  `verify-userland.sh` only prompts for
  `sudo` interactively when the board requires it.

## Non-goals

- Not a Flathub submission for JMP or the VacuumTube fork.
- The VacuumTube fork is personal and deliberately not published under the real
  app ID; the official Flathub app remains `rocks.shy.VacuumTube`.
- Kernel deployment is deliberately manual and confirmation-driven.  There is
  no automated kernel uninstall/reinstall verification script.

## License

See `LICENSE-NOTES.md`.  The Flatpak bundles GPL FFmpeg/mpv/JMP code; the
VacuumTube fork carries MIT-licensed app code and the MIT/LGPL driver fork.
These are personal builds and are not intended for Flathub.
