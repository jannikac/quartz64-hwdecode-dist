#!/bin/sh
# Build and export the personal VacuumTube V4L2 Flatpak from the manifest.
#
# On a native aarch64 host this is a plain flatpak-builder build.
#
# On an x86_64 host it also stays manifest-driven: flatpak-builder runs inside
# an unprivileged user namespace with a sandboxed binfmt_misc entry for
# qemu-aarch64.  That lets the aarch64 SDK/node22 toolchain execute without
# root, without editing any host configuration, and without a global binfmt
# registration.  A temporary manifest copy adds "--filesystem=/nix:ro" to the
# manifest's existing build-options so the qemu interpreter from the Nix
# store is visible inside flatpak-builder's sandbox.  Same mechanism as
# jellyfin-flatpak/build-flatpak.sh; see that script for the rationale and
# the two cross-build approaches that were tried and failed first.
#
# Environment:
#   ARCH        flatpak architecture (default: aarch64)
#   REPO        output repository directory (default: ./repo)
#   DIST        bundle output directory (default: ./dist)
#   BUILDDIR    flatpak-builder work directory (default: ./build-dir)

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
self=$here/$(basename -- "$0")
app_id=dev.jannik.VacuumTubeV4L2
arch=${ARCH:-aarch64}
repo=${REPO:-$root/repo}
dist=${DIST:-$root/dist}
builddir=${BUILDDIR:-$root/build-dir}
state_dir=${STATE_DIR:-$root/.flatpak-builder}
manifest=$root/dev.jannik.VacuumTubeV4L2.yml
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
		--state-dir="$VAC_STATE_DIR" --repo="$VAC_REPO" \
		--disable-rofiles-fuse --force-clean --arch="$VAC_ARCH" \
		"$VAC_BUILDDIR" "$VAC_HOST_MANIFEST"
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

	tmp_manifest=$(mktemp "$root/.host-manifest.XXXXXX.yml")
	trap 'rm -f "$tmp_manifest"' EXIT HUP INT TERM
	# Merge into the manifest's existing top-level build-options: block
	# (it already has append-path: for node22) rather than assuming none
	# exists.
	awk '
		/^build-options:/ && !done {
			print
			print "  build-args:"
			print "    - --filesystem=/nix:ro"
			done = 1
			next
		}
		{ print }
	' "$manifest" > "$tmp_manifest"
	grep -q -- '--filesystem=/nix:ro' "$tmp_manifest" ||
		die "could not inject the /nix build-arg into $manifest; check its build-options: block"

	VAC_STATE_DIR=$state_dir VAC_REPO=$repo VAC_BUILDDIR=$builddir \
	VAC_ARCH=$arch VAC_HOST_MANIFEST=$tmp_manifest \
		unshare -Urm --propagation private sh "$self" --host-inner
fi

flatpak build-bundle --arch="$arch" \
	--runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
	"$repo" "$bundle" "$app_id"

sha256sum "$bundle" | tee "$bundle.sha256"
