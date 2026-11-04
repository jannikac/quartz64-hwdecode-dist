#!/bin/sh
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(realpath "$here/..")
template="$root/boot-deploy/extlinux.conf.in"
service="$root/boot-deploy/clear-initramfs-eth0.service"
extlinux=/boot/extlinux/extlinux.conf
stock_extlinux=$extlinux.stock
stock_dtb=/boot/rk3566-quartz64-b.dtb
stock_initramfs=/boot/initramfs
artifacts=
assume_yes=0
dry_run=0

usage() {
    printf 'usage: sudo %s [--artifacts DIR] [--stock-initramfs FILE] [--dry-run] [--yes]\n' "$0" >&2
    exit 2
}

die() { printf 'deploy-kernel: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --artifacts) artifacts=$2; shift 2 ;;
        --stock-initramfs) stock_initramfs=$2; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        --yes) assume_yes=1; shift ;;
        -h|--help) usage ;;
        *) usage ;;
    esac
done

[ "$(id -u)" -eq 0 ] || die "run as root"
for tool in tar zstd depmod modinfo install sed sha256sum systemctl; do
    command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool"
done

if [ -z "$artifacts" ]; then
    count=$(find "$root/dist" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    [ "$count" -eq 1 ] || die "specify --artifacts (found $count directories under $root/dist)"
    artifacts=$(find "$root/dist" -mindepth 1 -maxdepth 1 -type d)
fi

[ -d "$artifacts" ] || die "artifacts directory not found: $artifacts"
for file in Image modules.tar.zst kernel.release; do
    [ -f "$artifacts/$file" ] || die "missing artifact: $artifacts/$file"
done
[ -f "$template" ] || die "missing template: $template"
[ -f "$service" ] || die "missing service file: $service"
[ -f "$here/repack-initramfs.sh" ] || die "missing $here/repack-initramfs.sh"
[ -f "$extlinux" ] || die "missing $extlinux"
[ -f "$stock_dtb" ] || die "missing $stock_dtb"
[ -f "$stock_initramfs" ] || die "missing $stock_initramfs"

if [ -f "$artifacts/SHA256SUMS" ]; then
    (cd "$artifacts" && sha256sum -c SHA256SUMS) || die "artifact checksum verification failed"
fi

release=$(tr -d '\n' < "$artifacts/kernel.release")
[ -n "$release" ] || die "empty kernel.release"
new_initramfs=/boot/initramfs-vp9
new_image=/boot/vmlinuz-vp9
new_dtb=/boot/rk3566-quartz64-b-vp9.dtb

uuid_from_fstab() {
    awk -v m="$1" '$1 ~ /^UUID=/ && $2 == m {
        sub(/^UUID=/, "", $1); print $1; exit
    }' /etc/fstab 2>/dev/null
}

dtb_has_decoder() {
    grep -aqE 'rockchip,rk3568-vdec|rockchip,rkv-decoder-rk3568|rkvdec' "$1"
}

uuid_for_mount() {
    _mountpoint=$1
    _uuid=$(uuid_from_fstab "$_mountpoint" || true)
    if [ -n "$_uuid" ]; then
        printf '%s\n' "$_uuid"
        return 0
    fi
    _uuid=$(findmnt -no UUID --target "$_mountpoint" 2>/dev/null || true)
    if [ -n "$_uuid" ]; then
        printf '%s\n' "$_uuid"
        return 0
    fi
    _source=$(findmnt -no SOURCE --target "$_mountpoint" 2>/dev/null || true)
    if [ -n "$_source" ] && command -v blkid >/dev/null 2>&1; then
        _uuid=$(blkid -s UUID -o value "$_source" 2>/dev/null || true)
        if [ -n "$_uuid" ]; then
            printf '%s\n' "$_uuid"
            return 0
        fi
    fi
    return 1
}

boot_uuid=$(uuid_for_mount /boot) || die "could not determine the /boot UUID"
root_uuid=$(uuid_for_mount /) || die "could not determine the root UUID"

if dtb_has_decoder "$stock_dtb"; then
    dtb_source=$stock_dtb
    dtb_reason="existing board DTB has an rkvdec node"
else
    dtb_source=$artifacts/rk3566-quartz64-b.dtb
    [ -f "$dtb_source" ] ||
        die "board DTB has no rkvdec node and kernel-built DTB is missing: $dtb_source"
    dtb_reason="board DTB has no rkvdec node; using the kernel-built DTB"
fi

cat <<EOF
About to deploy kernel $release

  artifacts:       $artifacts
  new image:       $new_image
  new initramfs:   $new_initramfs
  new DTB copy:    $new_dtb (from $dtb_source; $dtb_reason)
  modules:         /usr/lib/modules/$release
  boot UUID:       $boot_uuid
  root UUID:       $root_uuid
  rollback copy:   $stock_extlinux
  boot backup:     /boot/stock-boot-before-vp9.tar

The stock $stock_dtb and stock initramfs are not modified.
Keep the SD card and the .stock rollback file with the board.

EOF

if [ "$dry_run" -eq 1 ]; then
    printf 'Dry run: no files were changed.\n'
    exit 0
fi

if [ "$assume_yes" -ne 1 ]; then
    printf 'Type "yes" to deploy: '
    read -r answer
    [ "$answer" = yes ] || die "aborted"
fi

if [ ! -e "$stock_extlinux" ]; then
    cp -a "$extlinux" "$stock_extlinux"
    printf 'Created rollback copy: %s\n' "$stock_extlinux"
else
    printf 'Keeping existing rollback copy: %s\n' "$stock_extlinux"
fi

if [ ! -e /boot/stock-boot-before-vp9.tar ]; then
    tar -C /boot -cf /boot/stock-boot-before-vp9.tar \
        extlinux/extlinux.conf vmlinuz initramfs rk3566-quartz64-b.dtb ||
        die "could not create /boot/stock-boot-before-vp9.tar"
    printf 'Created boot backup: /boot/stock-boot-before-vp9.tar\n'
else
    printf 'Keeping existing boot backup: /boot/stock-boot-before-vp9.tar\n'
fi

temporary=$(mktemp -d "${TMPDIR:-/tmp}/deploy-kernel.XXXXXX")
trap 'rm -rf "$temporary"' EXIT

sh "$here/repack-initramfs.sh" \
    --stock-initramfs "$stock_initramfs" \
    --modules "$artifacts/modules.tar.zst" \
    --release "$release" \
    --output "$temporary/initramfs-vp9"

sed -e "s|@PMOS_BOOT_UUID@|$boot_uuid|g" \
    -e "s|@PMOS_ROOT_UUID@|$root_uuid|g" \
    "$template" > "$temporary/extlinux.conf"
if grep -q '@PMOS_' "$temporary/extlinux.conf"; then
    die "UUID substitution failed"
fi

zstd -t "$artifacts/modules.tar.zst"
rm -rf "/usr/lib/modules/$release"
zstd -dc "$artifacts/modules.tar.zst" | tar -xf - -C /
depmod -a "$release"
modinfo -k "$release" rockchip-vdec >/dev/null

install -m 0644 "$artifacts/Image" "$new_image"
install -m 0644 "$temporary/initramfs-vp9" "$new_initramfs"
install -m 0644 "$dtb_source" "$new_dtb"
install -m 0644 "$temporary/extlinux.conf" "$extlinux"
install -m 0644 "$service" /etc/systemd/system/clear-initramfs-eth0.service
systemctl daemon-reload
systemctl enable clear-initramfs-eth0.service
sync

cat <<EOF

Deployed kernel $release.

Rollback if the custom entry fails:
  power off, remove the SD card, mount partition 1, then restore
  extlinux/extlinux.conf from extlinux/extlinux.conf.stock
  (also available in /boot/stock-boot-before-vp9.tar).

Smoke tests after reboot:
  kernel-patches-dist/scripts/test-vp9.sh
  kernel-patches-dist/scripts/test-vp9-4k.sh
  kernel-patches-dist/scripts/test-h265.sh
  kernel-patches-dist/scripts/test-h265-4k.sh
  kernel-patches-dist/scripts/test-h264.sh
  kernel-patches-dist/scripts/test-h264-4k.sh

Do not reboot until you are physically at the board or have SD-card access.
EOF
