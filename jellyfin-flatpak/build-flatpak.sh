#!/bin/sh
# Build and export the personal Jellyfin Desktop V4L2 Flatpak.
#
# Run this on an aarch64 host with flatpak-builder, or on an x86_64 host with
# aarch64 binfmt/qemu-user configured.  The target board has less than 1 GB
# free and cannot hold the org.kde.Sdk build tree, so build elsewhere and copy
# only the exported .flatpak bundle.
#
# Environment:
#   ARCH        flatpak architecture (default: host architecture)
#   REPO        output repository directory (default: ./repo)
#   DIST        bundle output directory (default: ./dist)
#   BUILDDIR    flatpak-builder work directory (default: ./build-dir)

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo=${REPO:-$here/repo}
dist=${DIST:-$here/dist}
builddir=${BUILDDIR:-$here/build-dir}
manifest=dev.jannik.JellyfinDesktopV4L2.yml
bundle=$dist/dev.jannik.JellyfinDesktopV4L2.flatpak

command -v flatpak-builder >/dev/null 2>&1 || {
	printf 'error: flatpak-builder not found\n' >&2
	exit 1
}

arch_args=
[ -n "${ARCH:-}" ] && arch_args="--arch=$ARCH"

mkdir -p "$dist"
# shellcheck disable=SC2086
flatpak-builder --user --install-deps-from=flathub \
	--repo="$repo" --force-clean $arch_args "$builddir" \
	"$here/$manifest"

# shellcheck disable=SC2086
flatpak build-bundle $arch_args --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
	"$repo" "$bundle" dev.jannik.JellyfinDesktopV4L2

sha256sum "$bundle" | tee "$bundle.sha256"
