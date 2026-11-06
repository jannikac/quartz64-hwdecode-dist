#!/bin/sh
# Build and export the personal Jellyfin Desktop V4L2 Flatpak from the manifest.
#
# On a native aarch64 host this is a plain flatpak-builder build.
#
# On an x86_64 host it also stays manifest-driven: flatpak-builder runs inside
# an unprivileged user namespace with a sandboxed binfmt_misc entry for
# qemu-aarch64.  That lets the aarch64 toolchain from the Flatpak SDK execute
# without root, without editing any host configuration, and without a global
# binfmt registration.  A temporary manifest copy adds
# "--filesystem=/nix:ro" so the QEMU interpreter from the Nix store is visible
# inside flatpak-builder's sandbox.
#
# Environment:
#   ARCH        flatpak architecture (default: aarch64)
#   REPO        output repository directory (default: ./repo)
#   DIST        bundle output directory (default: ./dist)
#   BUILDDIR    flatpak-builder work directory (default: ./build-dir)

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
self=$here/$(basename -- "$0")
app_id=dev.jannik.JellyfinDesktopV4L2
arch=${ARCH:-aarch64}
repo=${REPO:-$here/repo}
dist=${DIST:-$here/dist}
builddir=${BUILDDIR:-$here/build-dir}
state_dir=${STATE_DIR:-$here/.flatpak-builder}
manifest=$here/dev.jannik.JellyfinDesktopV4L2.yml
bundle=$dist/$app_id.flatpak

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1 (run inside nix-shell)"; }

# ---------------------------------------------------------------------------
# Inner mode: already inside the unprivileged user/mount namespace.
# Register qemu-aarch64 locally, then let flatpak-builder run the manifest.
# ---------------------------------------------------------------------------
if [ "${1:-}" = --host-inner ]; then
	need flatpak-builder
	qemu=$(command -v qemu-aarch64) || die "qemu-aarch64 not found"
	binfmt_dir=$(mktemp -d)
	mount -t binfmt_misc binfmt_misc "$binfmt_dir"
	line=':qemu-aarch64:M::\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:'"$qemu"':PF'
	printf '%s\n' "$line" > "$binfmt_dir/register"

	exec flatpak-builder --user --install-deps-from=flathub \
		--state-dir="$JMP_STATE_DIR" --repo="$JMP_REPO" \
		--disable-rofiles-fuse --force-clean --arch="$JMP_ARCH" \
		"$JMP_BUILDDIR" "$JMP_HOST_MANIFEST"
fi

need flatpak
need flatpak-builder
mkdir -p "$dist"

host_arch=$(uname -m)
if [ "$arch" = "$host_arch" ]; then
	flatpak-builder --user --install-deps-from=flathub \
		--state-dir="$state_dir" --repo="$repo" \
		--force-clean --arch="$arch" "$builddir" "$manifest"
else
	[ "$arch" = aarch64 ] ||
		die "host cross-build is only implemented for aarch64 (got $arch on $host_arch)"
	need unshare
	need qemu-aarch64
	grep -q '^build-options:' "$manifest" &&
		die "manifest already has top-level build-options; merge the /nix build-arg into it"

	tmp_manifest=$(mktemp "$here/.host-manifest.XXXXXX.yml")
	trap 'rm -f "$tmp_manifest"' EXIT HUP INT TERM
	awk '
		/^command:/ && !done {
			print
			print ""
			print "build-options:"
			print "  build-args:"
			print "    - --filesystem=/nix:ro"
			done = 1
			next
		}
		{ print }
	' "$manifest" > "$tmp_manifest"

	JMP_STATE_DIR=$state_dir JMP_REPO=$repo JMP_BUILDDIR=$builddir \
	JMP_ARCH=$arch JMP_HOST_MANIFEST=$tmp_manifest \
		unshare -Urm --propagation private sh "$self" --host-inner
fi

flatpak build-bundle --arch="$arch" \
	--runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
	"$repo" "$bundle" "$app_id"

sha256sum "$bundle" | tee "$bundle.sha256"
