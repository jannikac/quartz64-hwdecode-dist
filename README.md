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
| `kernel-patches-dist/` | Placeholder for a future pass. **Not implemented.**  Will eventually package the kernel-side patches from SRC as an installable artifact. |

### Why the split

- JMP's hardware decode needs mpv/FFmpeg with the `v4l2request` hwaccel.
  The Flatpak therefore builds its own FFmpeg and mpv under `/app`.
- Moving from Alpine/musl to a glibc Flatpak changes the old single-FFmpeg
  constraint.  Milestone 1 in `jellyfin-flatpak/README.md` records the actual
  finding: the KDE/base-app Qt WebEngine has no dynamic `libav*` dependency, so
  the Alpine parity patch is not needed here.  This was measured, not assumed.
- VacuumTube is Electron/Chromium, not mpv/GStreamer.  It can only use a VA-API
  driver.  A Flatpak cannot apply a `flatpak override` to another installed
  app from inside its sandbox, and repackaging someone else's signed Electron
  app under a new app ID is not appropriate.  Hence `vacuumtube-vaapi/` is a
  host-side script set that leaves the upstream Flathub app in place.
- `--device=all` is accepted for the JMP Flatpak because the V4L2 media
  controller has no Flatpak portal.  This is one reason the build is explicitly
  not for Flathub.

## End-user guide (install and use)

This is for someone with a Quartz64-B that already boots the working 7.3
kernel and wants the two hardware-decoded apps.  You do **not** need to build
anything if you already have these two files from the repo owner:

```text
dev.jannik.JellyfinDesktopV4L2.flatpak
v4l2_request_drv_video.so
```

If you do not have them, use the build/development quick start below, or ask
the repo owner for the matching bundle and driver.

### Before you start

- The board must be running the `7.3.0-quartz64-vp9+` kernel with a bound
  `rkvdec` device.  Kernel work is **not** part of this repository yet.
- Use a Wayland session.  Chromium's zero-copy video import does not work on
  X11 in this stack.
- Have Flathub configured and the official VacuumTube app installed:

  ```sh
  flatpak remote-add --if-not-exists --user flathub \
    https://flathub.org/repo/flathub.flatpakrepo
  flatpak install --user flathub rocks.shy.VacuumTube
  ```

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

### 2. Install the VacuumTube VA-API driver

VacuumTube itself stays the normal Flathub build.  Copy the driver to the board
and run the installer:

```sh
cd /path/to/quartz64-hwdecode-dist

./vacuumtube-vaapi/scripts/install-driver-override.sh \
  /path/to/v4l2_request_drv_video.so

./vacuumtube-vaapi/scripts/configure-vacuumtube.sh
```

Then start VacuumTube normally from its desktop entry.  The override applies
only to `rocks.shy.VacuumTube`; other Flatpak apps are unaffected.

To check hardware decode while a VP9 video plays:

```sh
./vacuumtube-vaapi/scripts/check-vacuumtube-hw.sh
```

Expected: the driver is mapped by a Chromium GPU process, the `rkvdec`
`/dev/video*` and `/dev/media*` nodes are open, and the `rkvdec` IRQ counter
increases.  In Chromium's `chrome://gpu`, video decode should say hardware
accelerated.

### What works and what does not

- Jellyfin: 8-bit H.264, HEVC, and VP9, including 4K, use `v4l2request`.
  10-bit HEVC currently captures NV15, which the compositor cannot import, so
  it may show blue or fall back to software.
- VacuumTube: only VP9 Profile 0 (8-bit) is supported by this driver fork.
  H.264, HEVC, AV1, and 10-bit VP9 are not hardware-decoded in VacuumTube.
- AV1 is not hardware-decoded on the RK3566 in either app.
- A Flatpak runtime update can change the libva ABI.  Rebuild/reinstall the
  VacuumTube driver after a `flatpak update` if hardware decoding stops working.

### Rollback

```sh
# Jellyfin Desktop personal build
flatpak uninstall --user dev.jannik.JellyfinDesktopV4L2

# VacuumTube driver/override only (leaves VacuumTube installed)
cd /path/to/quartz64-hwdecode-dist
./vacuumtube-vaapi/scripts/uninstall-vacuumtube-v4l2.sh
```

Neither rollback touches the kernel, DTBs, modules, bootloader, or the official
Flathub apps.

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

Build on a capable aarch64 host (or an x86_64 host with aarch64 binfmt), then
copy only the exported bundle to the board:

```sh
cd jellyfin-flatpak
./build-flatpak.sh                  # ARCH=aarch64 on an x86_64 build host
scp dist/dev.jannik.JellyfinDesktopV4L2.flatpak \
  jannik@192.168.1.203:/tmp/
```

On the board:

```sh
flatpak install --user --noninteractive \
  /tmp/dev.jannik.JellyfinDesktopV4L2.flatpak
flatpak run dev.jannik.JellyfinDesktopV4L2
```

See `jellyfin-flatpak/README.md` for pins, patch rationale, Milestone 1, and
verification details.

### 2. VacuumTube VA-API driver

VacuumTube stays the official Flathub build.  Build the driver on a host with
an aarch64 glibc cross compiler, then install it on the board:

```sh
scp /tmp/vacuumtube-driver/v4l2_request_drv_video.so \
  jannik@192.168.1.203:/tmp/

ssh jannik@192.168.1.203 '
  cd /path/to/quartz64-hwdecode-dist
  ./vacuumtube-vaapi/scripts/install-driver-override.sh \
    /tmp/v4l2_request_drv_video.so
  ./vacuumtube-vaapi/scripts/configure-vacuumtube.sh
'
```

See `vacuumtube-vaapi/README.md` for the full build and verification flow.

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

Usage:

```sh
# The script uses ordinary key-based SSH; it never stores a password.
BOARD=jannik@192.168.1.203 ./verify-userland.sh --yes

# If your artifacts are not in the default locations:
JELLYFIN_FLATPAK_BUNDLE=/path/to/dev.jannik.JellyfinDesktopV4L2.flatpak \
VA_DRIVER_SO=/path/to/v4l2_request_drv_video.so \
BOARD=jannik@192.168.1.203 ./verify-userland.sh --yes
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

## Non-goals for this pass

- Not a Flathub submission for JMP.
- No fork or rebuild of VacuumTube.
- `kernel-patches-dist/` is not populated beyond its README.
- No kernel, DTB, bootloader, or boot-entry changes.  Only userland packages,
  Flatpaks, and Flatpak overrides are in scope.

## License

See `LICENSE-NOTES.md`.  The Flatpak bundles GPL FFmpeg/mpv/JMP code; this is
another reason it is a personal build and is not intended for Flathub.
