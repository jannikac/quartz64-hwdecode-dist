# Quartz64-B kernel package (`7.3.0-quartz64-vp9+`)

This directory builds and deploys the custom kernel used by the hardware-decode
userland in this repository.  It is the minimal kernel-side package, not a copy
of the full board bring-up repository.

The deployed kernel is a `chewitt/linux` `rockchip-7.3.y` build with two
Rockchip `rockchip_vdec` / V4L2 driver patches.  The resulting board has a bound
`rkvdec` device that GStreamer, FFmpeg, mpv, and the Flatpak apps can use.

## Pins

| Input | Pin |
|---|---|
| Kernel source | `https://github.com/chewitt/linux.git`, branch `rockchip-7.3.y`, commit `2f895da2120e63197008b697ac26388c3dc4d742` |
| Patch 0001 | `patches/0001-rkvdec-initial-correctness.patch`, SHA-256 `71eb6fb79038ad03ca87b3fdcd4a5de859562afb2d443ed6bcd76a785a3262e9` |
| Patch 0002 | `patches/0002-rkvdec-vdpu346-recovery.patch`, SHA-256 `603b209c56deb30fa65f329a5fe5a63384cbfd7a265a529e46e22bac358b6fdc` |
| Kernel config | `kernel.config`, SHA-256 `8b377fa7419469ac8435dea04bb54b162e73eb7a8c0c6bdeee156965b04eda2c` |
| Release | `7.3.0-quartz64-vp9+` |

`kernel.config` is the already-resolved configuration from the validated build.
The two patch hashes and the config hash were checked against the source
repository's `artifacts/7.3.0-quartz64-vp9+/SHA256SUMS` before being copied
here.  The build script uses this file directly and runs `olddefconfig`; it does
not need a live board config snapshot first.

## DTB selection

The deploy script prefers the board's existing `/boot/rk3566-quartz64-b.dtb`
when it contains an rkvdec decoder node.  That preserves any board-specific
clock overrides.

A freshly reflashed stock postmarketOS v26.06 DTB can lack the rkvdec node
entirely; that was observed on the clean-board integration test.  In that case
the build ships the DTB generated from the pinned `rockchip-7.3.y` kernel,
which contains the mainline `rockchip,rk3568-vdec` node and its assigned
clocks.  The deploy script uses that kernel-built DTB only when the board DTB
has no decoder node.

Either way the chosen DTB is copied to
`/boot/rk3566-quartz64-b-vp9.dtb`.  The stock DTB file itself is never
overwritten.

## What is intentionally omitted

- **The kexec path is not included.**  kexec faults on the stock kernel's CFI
  check, so the real deployment goes through the SD card boot partition.  Only
  the initramfs module-swap part of the old kexec preparation is retained.
- **The abandoned vendor MPP driver port is not included.**  The MPP evidence,
  clock/watchdog dmesg logs, and related board-snapshot files are forensics
  from a dead end and are not needed to reproduce this kernel.
- **The stock 7.0.14 out-of-tree module is not part of this package.**  It was
  the first validated fallback before the custom kernel existed.  It is
  historical only and is not needed for the current deployment.
- **No clang/KCFI build.**  The custom kernel uses a plain GCC aarch64 cross
  toolchain.  The clang/KCFI constraint in the older notes applied to the
  unrelated stock-module build.

## Layout

```text
kernel-patches-dist/
  kernel.config
  patches/
    0001-rkvdec-initial-correctness.patch
    0002-rkvdec-vdpu346-recovery.patch
  scripts/
    build-kernel.sh
    repack-initramfs.sh
    deploy-kernel.sh
    test-vp9.sh
    test-vp9-4k.sh
    test-h265.sh
    test-h265-4k.sh
    test-h264.sh
    test-h264-4k.sh
  boot-deploy/
    extlinux.conf.in
    clear-initramfs-eth0.service
```

Build outputs go under `build/` and `dist/` and are not tracked.

## Building

Use the repository's cross shell, which provides the GCC aarch64 toolchain and
the kernel build tools:

```sh
cd quartz64-hwdecode-dist
nix-shell
./kernel-patches-dist/scripts/build-kernel.sh
```

The script:

1. Clones or fetches the pinned commit into `build/linux`.
2. Applies the two pinned patches.
3. Copies `kernel.config`, runs `olddefconfig`, and builds
   `Image modules rockchip/rk3566-quartz64-b.dtb`.
4. Installs modules into a staging tree and writes:

```text
dist/7.3.0-quartz64-vp9+/
  Image
  modules.tar.zst
  rk3566-quartz64-b.dtb
  kernel.release
  kernel.config
  source-revision
  SHA256SUMS
```

## Repacking the initramfs

`scripts/repack-initramfs.sh` is the retained part of the old kexec
preparation.  It:

1. Extracts the stock gzip-compressed cpio initramfs.
2. Verifies the board's `init`, `init_2nd.sh`, and `lib -> usr/lib` layout.
3. Removes only the versioned module directories under `usr/lib/modules/`.
4. Installs the new release's modules, runs `depmod -b`, and checks that
   `rockchip-vdec` resolves.
5. Repacks as reproducible cpio + gzip.

It does **not** patch MAC address, serial number, memory reservation, or any
other DTB property.  That block was kexec-only and is gone.

`deploy-kernel.sh` calls this script automatically with the board's existing
`/boot/initramfs` and the build's `modules.tar.zst`.

## Deploying

The deploy and initramfs scripts run on the board.  A stock postmarketOS
v26.06 install is missing `zstd`, so install it first:

```sh
sudo apk add zstd
```

`cpio`, `gzip`, and kmod (`depmod`/`modinfo`/`modprobe`) are already present
on the stock image.

Copy the package and the built artifacts from the build host without the large
`build/` tree:

```sh
# On the build host, from the repository root:
tar --exclude='kernel-patches-dist/build' -cf - kernel-patches-dist |
  ssh user@board '
    mkdir -p ~/quartz64-hwdecode-dist
    tar -C ~/quartz64-hwdecode-dist -xf -'
```

Run on the board as root.  The script is deliberately interactive and does not
reboot automatically:

```sh
cd ~/quartz64-hwdecode-dist
sudo ./kernel-patches-dist/scripts/deploy-kernel.sh \
  --artifacts ./kernel-patches-dist/dist/7.3.0-quartz64-vp9+
```

Add `--dry-run` first if you want to see the detected UUIDs and target files
without changing anything:

```sh
sudo ./kernel-patches-dist/scripts/deploy-kernel.sh \
  --artifacts /path/to/dist/7.3.0-quartz64-vp9+ --dry-run
```

The script performs the following, with an explicit confirmation prompt:

1. Verifies `SHA256SUMS` when present.
2. Reads the board's own `/boot` and `/` UUIDs from `/etc/fstab`, falling back
   to `findmnt`/`blkid`.  It does not contain hardcoded UUIDs from another
   board.
3. Creates `/boot/extlinux/extlinux.conf.stock` if it does not already exist.
   An existing `.stock` file is preserved as the rollback reference.
4. Creates `/boot/stock-boot-before-vp9.tar` if it does not already exist.
5. Repacks the initramfs with the new modules.
6. Installs modules under `/usr/lib/modules/<release>` and runs `depmod`.
7. Selects the board DTB when it has an rkvdec node, otherwise uses the
   kernel-built DTB, and copies the selected file to
   `/boot/rk3566-quartz64-b-vp9.dtb`.
8. Installs `/boot/vmlinuz-vp9` and `/boot/initramfs-vp9`.
9. Writes a dual-entry `/boot/extlinux/extlinux.conf` with the stock entry and
   the new `quartz64-vp9-test` entry.  Both entries use the detected UUIDs and
   `cma=256M`.
10. Installs and enables `clear-initramfs-eth0.service`, which clears the
    initramfs USB-network address from `eth0` so NetworkManager can DHCP.

The stock `vmlinuz`, `initramfs`, `rk3566-quartz64-b.dtb`, and stock entry
remain present.  The kernel-built DTB, when needed, is installed only as the
new `rk3566-quartz64-b-vp9.dtb` filename.

Reboot manually when you are at the board or have SD-card access:

```sh
sudo reboot
```

Expected after boot:

```sh
uname -r
# 7.3.0-quartz64-vp9+

cat /sys/class/video4linux/video*/name
# includes rkvdec
```

## Rollback

The proven rollback is the `.stock` extlinux copy on the SD card:

```sh
sudo cp /boot/extlinux/extlinux.conf.stock /boot/extlinux/extlinux.conf
sudo reboot
```

If the board cannot boot, power off, remove the SD card, mount partition 1 on
another machine, and restore `extlinux/extlinux.conf` from
`extlinux/extlinux.conf.stock`.  The same stock files are also in
`/boot/stock-boot-before-vp9.tar` when it was created.

Keep the SD card and the `.stock` file with the board.  Removing them removes
the easy recovery path.

## Smoke tests

A fresh postmarketOS install has the GStreamer libraries but not the command
line tools or the Good plugins.  Install them first:

```sh
sudo apk add gstreamer-tools gst-plugins-good gst-plugins-bad
```

The six original board tests are included unchanged.  They do not bundle media
files; the default paths are from the original development board.  Pass your
own local files explicitly:

```sh
./kernel-patches-dist/scripts/test-vp9.sh     /path/to/test-vp9.webm
./kernel-patches-dist/scripts/test-vp9-4k.sh  /path/to/test-vp9-4k.webm
./kernel-patches-dist/scripts/test-h265.sh    /path/to/test-h265.mkv
./kernel-patches-dist/scripts/test-h265-4k.sh /path/to/test-h265-4k.mkv
./kernel-patches-dist/scripts/test-h264.sh    /path/to/test-h264.mkv
./kernel-patches-dist/scripts/test-h264-4k.sh /path/to/test-h264-4k.mkv
```

They use GStreamer's `v4l2sl*` decoders, locate the `rkvdec` device by name,
and print `PASS` or `FAIL`.  Set `SINK=waylandsink` to display the output
instead of using `fakesink`.

The userland checks in the top-level repository (`jellyfin-flatpak/` and
`vacuumtube-vaapi/`) are separate; this kernel package only proves that the
kernel and GStreamer stack decode with `rkvdec`.

## Risk

A bad kernel or boot install is much more disruptive than a bad userland
package.  It can leave the board needing physical SD-card recovery.  The deploy
script therefore requires root, shows exactly what it will change, asks for
confirmation, preserves `.stock`, and never reboots automatically.  Keep the
SD card and the `.stock` backup; do not run an unattended uninstall/reinstall
loop for the kernel.
