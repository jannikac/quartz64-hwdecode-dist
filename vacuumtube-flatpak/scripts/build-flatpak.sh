#!/bin/sh
# Build and export the personal VacuumTube V4L2 Flatpak.
#
# Run this on an aarch64 host with flatpak-builder, or on an x86_64 host with
# aarch64 binfmt/qemu-user configured.  This build compiles Electron's npm
# sources and does not use the custom cross-toolchain path that the Jellyfin
# Flatpak uses.
#
# Environment:
#   ARCH        flatpak architecture (default: host architecture)
#   REPO        output repository directory (default: ./repo)
#   DIST        bundle output directory (default: ./dist)
#   BUILDDIR    flatpak-builder work directory (default: ./build-dir)

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
repo=${REPO:-$root/repo}
dist=${DIST:-$root/dist}
builddir=${BUILDDIR:-$root/build-dir}
manifest=dev.jannik.VacuumTubeV4L2.yml
bundle=$dist/dev.jannik.VacuumTubeV4L2.flatpak

command -v flatpak-builder >/dev/null 2>&1 || {
	printf 'error: flatpak-builder not found\n' >&2
	exit 1
}

arch_args=
info_args=
[ -n "${ARCH:-}" ] && arch_args="--arch=$ARCH"
[ -n "${ARCH:-}" ] && info_args="--arch=$ARCH"

deps_args=
if ! flatpak info $info_args org.freedesktop.Sdk//25.08 >/dev/null 2>&1 ||
   ! flatpak info $info_args org.electronjs.Electron2.BaseApp//25.08 >/dev/null 2>&1 ||
   ! flatpak info $info_args org.freedesktop.Sdk.Extension.node22//25.08 >/dev/null 2>&1; then
	deps_args="--install-deps-from=flathub"
fi

mkdir -p "$dist"
# shellcheck disable=SC2086
flatpak-builder --user $deps_args \
	--repo="$repo" --force-clean $arch_args "$builddir" \
	"$root/$manifest"

# shellcheck disable=SC2086
flatpak build-bundle $arch_args --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
	"$repo" "$bundle" dev.jannik.VacuumTubeV4L2

sha256sum "$bundle" | tee "$bundle.sha256"
