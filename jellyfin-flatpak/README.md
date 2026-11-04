# Jellyfin Desktop Flatpak with V4L2 Request hardware decode

This directory builds a **personal, sideloaded** Flatpak of Jellyfin Desktop
(Jellyfin Media Player, "JMP") 2.0.0 with a patched FFmpeg 8.1.1 and mpv 0.41.0
that use the Linux kernel's V4L2 Request stateless API (`v4l2request` hwaccel)
on the Pine64 Quartz64 Model B (RK3566 / `rkvdec`).

> **Not for Flathub.** This is a local build for one board. It uses
> `--device=all`, carries a personal app ID, and bundles GPL FFmpeg/mpv/JMP
> code. Do not submit it to Flathub.

Jellyfin already publishes an official Flathub app ID,
`org.jellyfin.JellyfinDesktop`. This build deliberately uses a different,
clearly personal ID:

```
dev.jannik.JellyfinDesktopV4L2
```

It is **not affiliated with or endorsed by the Jellyfin project**. It exists
only because upstream JMP does not ship the `v4l2request` stateless hwaccel or
the RK3566 driver support enabled in this configuration.

The original working Alpine/musl `/opt` APK build remains in the board bring-up
repository, `/home/jannik/Development/quartz64-b-hvec-vp9-decoder-deepseek`
(referred to as SRC in this document).

## Milestone 1 — Qt WebEngine / FFmpeg de-risking

This was checked on the board before choosing the manifest design.

The KDE runtime (`org.kde.Platform//6.11`) does **not** contain Qt WebEngine.
The official Flathub JMP app gets it from the base app
`io.qt.qtwebengine.BaseApp//6.11`. Inside the installed official JMP Flatpak,
`/app/lib/aarch64-linux-gnu/libQt6WebEngineCore.so.6.11.2` was inspected:

```text
$ readelf -d libQt6WebEngineCore.so.6.11.2 | grep NEEDED
... libQt6WebChannel.so.6, libQt6Positioning.so.6, libQt6Quick.so.6,
    libQt6Gui.so.6, libQt6Qml.so.6, libQt6Network.so.6, libQt6Core.so.6,
    libicu*, libnss*, libgio*, libgbm*, libopus*, libX*, ...
```

There is **no `libavcodec.so`, `libavformat.so`, `libavutil.so` or
`libavfilter.so` in the `NEEDED` list**, and no undefined `av_*` symbol in the
library. Qt WebEngine carries Chromium's private FFmpeg inside the WebEngine
library rather than dynamically linking a public FFmpeg.

### Implications

- The musl-era rule "the whole JMP process, including WebEngine, must load one
  FFmpeg" was a workaround for Alpine's Qt WebEngine dynamically linking
  Alpine FFmpeg 8.1.3. It **does not apply to this base app**.
- The old Alpine `add-av_stream_get_first_dts-for-chromium.patch` is **not
  needed**. It existed to satisfy the Alpine WebEngine's dynamic FFmpeg
  references. The KDE/base-app WebEngine has no such references.
- The Alpine `posix-ioctl.patch` is **not needed**. It is a musl/libv4l2 build
  workaround; this is a glibc build and `--enable-libv4l2` is not used.
- We still keep our FFmpeg and mpv entirely inside `/app` and do not put their
  directory on a global `LD_LIBRARY_PATH` for WebEngine. Our FFmpeg has SONAME
  `libavcodec.so.62` while the runtime has `libavcodec.so.61`, so there is no
  SONAME collision.
- Residual risk: a non-mpv part of JMP could load the runtime FFmpeg through
  Qt Multimedia. The official app's dynamic dependencies do not show that, and
  the verification checks below look for unexpected FFmpeg mappings. If that
  changes in a future base app, re-check this section rather than assuming the
  constraint is still gone.

## Pinned inputs

| Input | Pin |
|---|---|
| FFmpeg source | 8.1.1 tarball, SHA-256 `b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3` |
| mpv source | 0.41.0 tarball, SHA-256 `ee21092a5ee427353392360929dc64645c54479aefdb5babc5cfbb5fad626209` |
| Jellyfin Desktop | tag `v2.0.0`, commit `1634d3d263b881dccc62bf278d1289b471ec7af1` |
| MpvQt | `invent.kde.org/libraries/mpvqt`, commit `2ebbd38bf65d01be9c55d673ecd43c8bb9a6fc8e` |
| libplacebo | tag `v7.351.0`, commit `3188549fba13bbdf3a5a98de2a38c2e71f04e21e` |
| libass | 0.17.4, SHA-256 `a886b3b80867f437bc55cff3280a652bfa0d37b43d2aff39ddf3c4f288b8c5a8` |
| Runtime / base | `org.kde.Platform//6.11`, `io.qt.qtwebengine.BaseApp//6.11` |
| Target | aarch64, Pine64 Quartz64 Model B, RK3566 `rkvdec` |

## Patches and why each is needed

| Patch | Why it is here |
|---|---|
| `patches/ffmpeg/0001-v4l2-drmprime.patch` | Exports V4L2 buffers as `AVDRMFrameDescriptor` so the decoder output can be imported zero-copy. From LibreELEC. |
| `patches/ffmpeg/0001-v4l2-request.patch` | The V4L2 Request stateless hwaccel and `v4l2request` pixel format support, including the RK3566/`rkvdec` codec paths. From LibreELEC. |
| `patches/ffmpeg/0001-vf-deinterlace-v4l2m2m.patch` | V4L2 m2m deinterlace filter used by the same stack; keeps parity with the working SRC build. |
| `patches/ffmpeg/0001-wip-hevc-Add-support-for-sps-st-rps-control.patch` | HEVC SPS short-term RPS control needed by the 7.3 kernel's stateless HEVC interface. |
| `patches/mpv/0001-mpv-v4l2request.patch` | Adds mpv's `v4l2request` / `v4l2request-copy` hwdecs and the meson detection option. |
| `patches/jellyfin-desktop/0001-jmp-v4l2request-reload.patch` | Selects `v4l2request` when JMP hardware decoding is enabled, fixes the installed RPATH to `/app/lib`, exposes a safe mpv IPC socket for verification, and reloads the web client once if the native `NativeShell` plugin did not register. |

Patch SHA-256 checksums:

```text
e32597441686d6f64096af210f16d29cf42dfc111225f0f1827a73c2b22e1fbd  patches/ffmpeg/0001-v4l2-drmprime.patch
afd04c202c27081c355d8d34b58a52c4141de26433007e27ed6e0d2093d10d3c  patches/ffmpeg/0001-v4l2-request.patch
2c195c22dc8dd7cfa87b2d876c5d4e97784d17a3797066748e3fddab25cbdf5f  patches/ffmpeg/0001-vf-deinterlace-v4l2m2m.patch
2b40e1f50060cb21651377350c547f71be66cfd9bc1937e0671787731698fa0a  patches/ffmpeg/0001-wip-hevc-Add-support-for-sps-st-rps-control.patch
41922bf07ee29cbf23e868c38891d60abfe8ccee5acc4571bcec6700f116c72b  patches/mpv/0001-mpv-v4l2request.patch
d6ff85831463b90121d9416d3bf58427bacffe8cd61e7650acf38e32ed325baf  patches/jellyfin-desktop/0001-jmp-v4l2request-reload.patch
```

### Re-evaluated SRC patches that are intentionally not included

The SRC FFmpeg patch set also contained two Alpine-specific patches. They were
reviewed against the glibc/KDE target rather than copied blindly:

| SRC patch | Decision |
|---|---|
| `alpine/add-av_stream_get_first_dts-for-chromium.patch` | **Dropped.** Needed only when Alpine's QtWebEngine dynamically links the host FFmpeg and references `av_stream_get_first_dts`. The KDE/base-app WebEngine has no `libav*` dependency (Milestone 1). |
| `alpine/posix-ioctl.patch` | **Dropped.** A musl/libv4l2 build fix. This build uses glibc and does not enable `--enable-libv4l2`; the V4L2 Request path does not need the libv4l2 shim. |

The adapter (`mkpkg.py`) and the whole Alpine/APK packaging path are not used
here.

## Building the Flatpak

The target board has less than 1 GB free. `org.kde.Sdk//6.11` plus a JMP build
tree does not fit there, so build on a capable aarch64 host, or on an x86_64
host with aarch64 binfmt/qemu-user configured, and copy only the exported
bundle. This is the same cross-build-then-copy pattern used for the
VacuumTube driver.

Requirements on the build host:

- `flatpak` and `flatpak-builder`
- a Flathub remote
- roughly 5 GB free for the SDK, base app, and build tree
- for x86_64: `qemu-user-static`/binfmt for aarch64

```sh
cd jellyfin-flatpak
flatpak remote-add --user --if-not-exists flathub \
  https://flathub.org/repo/flathub.flatpakrepo

./build-flatpak.sh
# or, on x86_64 with aarch64 binfmt:
# ARCH=aarch64 ./build-flatpak.sh
```

The script runs `flatpak-builder` and exports:

```text
dist/dev.jannik.JellyfinDesktopV4L2.flatpak
dist/dev.jannik.JellyfinDesktopV4L2.flatpak.sha256
```

If the SDK's UAPI headers are too old for the V4L2 Request stateless controls,
build against a newer `linux/videodev2.h`. Do not replace the board kernel or
copy kernel patches into this repository; the kernel side is deliberately
deferred to `kernel-patches-dist/`.

## Installing on the board

Copy only the bundle:

```sh
scp dist/dev.jannik.JellyfinDesktopV4L2.flatpak \
  jannik@192.168.1.203:/tmp/

ssh jannik@192.168.1.203 '
  flatpak install --user --noninteractive \
    /tmp/dev.jannik.JellyfinDesktopV4L2.flatpak
'
```

The bundle declares `org.kde.Platform//6.11` and
`io.qt.qtwebengine.BaseApp//6.11`. If they are not already present on the
board, install them from Flathub first:

```sh
flatpak install --user flathub \
  org.kde.Platform//6.11 \
  io.qt.qtwebengine.BaseApp//6.11
```

Run it:

```sh
flatpak run dev.jannik.JellyfinDesktopV4L2
```

Log in with your own Jellyfin account, open **Client Settings → Hardware
Decoding**, and enable hardware decoding. The patch makes the `enabled` mode use
`hwdec=v4l2request` instead of `auto`.

## Sandbox and permissions

`finish-args` intentionally include:

- `--device=all` — required for `/dev/video*`, `/dev/media*` and the media
  controller used by the stateless decoder. `--device=dri` alone is not enough.
- `--socket=wayland`, `--socket=fallback-x11`
- `--socket=pulseaudio`
- `--share=ipc`, `--share=network`

`--device=all` is a deliberate sandbox weakening accepted for this personal
build. It is one of the reasons this manifest is not suitable for Flathub.

The verification socket is placed under the app's own host-backed cache
directory (`~/.var/app/dev.jannik.JellyfinDesktopV4L2/cache/jmp-video.sock`),
not in the sandbox-private `/tmp`, so the host-side check script can query safe
player properties without granting access to the host `/tmp`.

## Verification

`scripts/check_jmp_hw.sh` is a host-side copy adapted from SRC's
`check_jmp_hw.sh`. It queries only codec/hwdec/player properties and
`/proc/<pid>/maps`; it never queries `media-title`, `path`, a stream URL, or any
Jellyfin credential.

1. Start the Flatpak and play a Jellyfin item (or a local test file through
   JMP) with hardware decoding enabled.
2. On the board, run:

   ```sh
   jellyfin-flatpak/scripts/check_jmp_hw.sh
   ```

Expected while playing:

```text
idle-active = False
hwdec = ['v4l2request']
hwdec-current = v4l2request
current-vo = libmpv
ok   /app/lib/libavcodec.so.62...
ok   /app/lib/libavutil.so.60...
ok   /app/lib/libmpv.so.2...
rkvdec_irq_delta_5s = <non-zero>
```

A `FAIL` line is printed for an idle player, a non-`v4l2request` hwdec, an
unexpected host FFmpeg/mpv mapping, or a non-increasing rkvdec IRQ counter.

A quick lower-level smoke test of the packaged FFmpeg/mpv (without a Jellyfin
login) can be run inside the sandbox on a local file:

```sh
flatpak run --filesystem="$HOME/test-claude:ro" \
  --command=sh dev.jannik.JellyfinDesktopV4L2 -c '
    mpv --no-config --hwdec=v4l2request --vo=null --frames=120 \
        --log-file=/tmp/mpv-smoke.log "/home/jannik/test-claude/test.vp9.webm"
    grep -oE "Using (hardware|software) decoding[^ ]*( \([a-z0-9-]+\))?" /tmp/mpv-smoke.log
  '
```

Expected: `Using hardware decoding (v4l2request)`.

Typical limitations are unchanged from SRC: 8-bit H.264/HEVC/VP9 work;
10-bit HEVC captures NV15 and is not importable; AV1 is not hardware-decoded on
RK3566.

## Rollback

```sh
flatpak uninstall --user dev.jannik.JellyfinDesktopV4L2
```

This does not touch the official `org.jellyfin.JellyfinDesktop` Flatpak, the
VacuumTube Flatpak, the kernel, DTBs, modules, or bootloader.

## Security notes

- Never commit or publish Jellyfin credentials, `cred.json`, API tokens, server
  URLs with keys, or playback logs containing stream URLs.
- The check script deliberately reads only hwdec/codec/player state and process
  maps.
- If a token appears in diagnostic output, invalidate it by logging out and
  back in.
