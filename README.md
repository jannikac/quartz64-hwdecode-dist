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

## Quick start

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
