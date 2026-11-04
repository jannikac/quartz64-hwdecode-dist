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

## Why the DTB is not rebuilt

The board's existing `/boot/rk3566-quartz64-b.dtb` already contains the vendor
RKVDEC node (`rockchip,rkv-decoder-rk3568`) and the 297 MHz clock overrides that
the mainline driver accepts.  A DTB produced from the kernel source tree may
not carry those same overrides.

The deploy script therefore copies the board's existing
`/boot/rk3566-quartz64-b.dtb` to `/boot/rk3566-quartz64-b-vp9.dtb`.  It never
overwrites the stock DTB and never uses a source-built DTB.  The build script
builds only `Image` and modules.

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
    test-h265.sh
    test-h265-4k.sh
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
3. Copies `kernel.config`, runs `olddefconfig`, and builds `Image modules`.
4. Installs modules into a staging tree and writes:

```text
dist/7.3.0-quartz64-vp9+/
  Image
  modules.tar.zst
  kernel.release
  kernel.config
  source-revision
  SHA256SUMS
```

It does not build or copy a DTB.

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

Run on the board as root.  The script is deliberately interactive and does not
reboot automatically:

```sh
cd /path/to/quartz64-hwdecode-dist
sudo ./kernel-patches-dist/scripts/deploy-kernel.sh \
  --artifacts /path/to/dist/7.3.0-quartz64-vp9+
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
7. Copies the board's existing DTB to `/boot/rk3566-quartz64-b-vp9.dtb`.
8. Installs `/boot/vmlinuz-vp9` and `/boot/initramfs-vp9`.
9. Writes a dual-entry `/boot/extlinux/extlinux.conf` with the stock entry and
   the new `quartz64-vp9-test` entry.  Both entries use the detected UUIDs and
   `cma=256M`.
10. Installs and enables `clear-initramfs-eth0.service`, which clears the
    initramfs USB-network address from `eth0` so NetworkManager can DHCP.

The stock `vmlinuz`, `initramfs`, `rk3566-quartz64-b.dtb`, and stock entry
remain present.  The script never writes a source-built DTB.

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

The four original board tests are included unchanged.  Run them on the board
after booting the custom entry:

```sh
./kernel-patches-dist/scripts/test-vp9.sh
./kernel-patches-dist/scripts/test-h265.sh
./kernel-patches-dist/scripts/test-h265-4k.sh
./kernel-patches-dist/scripts/test-h264-4k.sh
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
