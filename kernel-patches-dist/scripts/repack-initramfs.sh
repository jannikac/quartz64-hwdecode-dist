#!/bin/sh
set -eu

usage() {
    printf 'usage: %s --stock-initramfs FILE --modules TAR_OR_DIR \\\n' "$0" >&2
    printf '          --release RELEASE --output FILE\n' >&2
    exit 2
}

stock=
modules=
release=
output=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --stock-initramfs) stock=$2; shift 2 ;;
        --modules) modules=$2; shift 2 ;;
        --release) release=$2; shift 2 ;;
        --output) output=$2; shift 2 ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
done
[ -n "$stock" ] && [ -n "$modules" ] && [ -n "$release" ] && [ -n "$output" ] || usage
[ -f "$stock" ] || { printf 'missing stock initramfs: %s\n' "$stock" >&2; exit 1; }
[ -e "$modules" ] || { printf 'missing modules input: %s\n' "$modules" >&2; exit 1; }

for tool in gzip cpio depmod modinfo modprobe find; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'missing required tool: %s\n' "$tool" >&2
        exit 1
    }
done

temporary=$(mktemp -d "${TMPDIR:-/tmp}/repack-initramfs.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
initrd="$temporary/initramfs"
modroot="$temporary/modules"
mkdir -p "$initrd" "$modroot"

gzip -t "$stock"
gzip -dc "$stock" |
    (cd "$initrd" && cpio -idm)

test -x "$initrd/init"
test -x "$initrd/init_2nd.sh"
test -L "$initrd/lib"
test "$(readlink "$initrd/lib")" = usr/lib

case "$modules" in
    *.tar.zst|*.tzst)
        command -v zstd >/dev/null 2>&1 || {
            printf 'missing required tool: zstd\n' >&2
            exit 1
        }
        zstd -dc "$modules" | tar -xf - -C "$modroot"
        ;;
    *.tar.gz|*.tgz)
        gzip -dc "$modules" | tar -xf - -C "$modroot"
        ;;
    *.tar)
        tar -xf "$modules" -C "$modroot"
        ;;
    *)
        [ -d "$modules" ] || {
            printf 'unsupported modules input: %s\n' "$modules" >&2
            exit 1
        }
        cp -a "$modules"/. "$modroot"/
        ;;
esac

test -d "$modroot/lib/modules/$release" || {
    printf 'modules input has no lib/modules/%s\n' "$release" >&2
    exit 1
}

for directory in "$initrd/usr/lib/modules/"*; do
    if [ -d "$directory" ] && [ ! -L "$directory" ]; then
        rm -rf "$directory"
    fi
done
cp -a "$modroot/lib/modules/$release" "$initrd/usr/lib/modules/"
depmod -b "$initrd" "$release"
modinfo -b "$initrd" -k "$release" rockchip-vdec >/dev/null
modprobe -d "$initrd" -S "$release" --show-depends rockchip-vdec >/dev/null

mkdir -p "$(dirname -- "$output")"
tmp_output=$output.tmp.$$
(
    cd "$initrd"
    find . -print | cpio -o -H newc | gzip -n -9
) > "$tmp_output"
mv "$tmp_output" "$output"
printf 'Repacked initramfs: %s\n' "$output"
