#!/bin/sh
# Configure the forked VacuumTube Flatpak for the VA-API (v4l2_request) path.
#
# - installs Chromium flags that keep VA-API enabled and select Wayland
# - enables VacuumTube's hardware decoding setting
# - filters YouTube codecs down to VP9 Profile 0, the only profile the
#   RK3566 rkvdec driver + libva fork can decode in this setup
#
# The LIBVA_* environment and the driver itself are already baked into the
# Flatpak.  This script only writes the app's normal user configuration.
#
# Run on the board as the desktop user.

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$here/../env.sh"

conf_dir=$HOME/.var/app/$APP_ID/config/VacuumTube
flags=$conf_dir/flags.txt
config=$conf_dir/config.json
stamp=$(date +%Y%m%d-%H%M%S)

mkdir -p "$conf_dir"

if [ -f "$flags" ]; then
	cp "$flags" "$flags.bak-$stamp"
fi

install -Dm644 "$here/../configs/flags.txt" "$flags"

tmp=$config.tmp.$$
if [ -f "$config" ]; then
	cp "$config" "$config.bak-$stamp"
	if command -v jq >/dev/null 2>&1; then
		jq '. +
			{
				hardware_decoding: true,
				h264ify: true,
				h264ify_disable_webm: false,
				h264ify_disable_vp8: true,
				h264ify_disable_vp9: false,
				h264ify_disable_av1: true
			}' "$config" > "$tmp"
		mv "$tmp" "$config"
	else
		printf '%s\n' \
			"warning: jq not found; $config not modified." \
			"Enable Hardware Decoding and Filter Video Codecs manually in VacuumTube settings:" \
			"  Hardware Decoding: on" \
			"  Filter Video Codecs: on; disable WebM=off, VP8=on, VP9=off, AV1=on" >&2
	fi
else
	cat > "$config" <<'EOF'
{
	"hardware_decoding": true,
	"h264ify": true,
	"h264ify_disable_webm": false,
	"h264ify_disable_vp8": true,
	"h264ify_disable_vp9": false,
	"h264ify_disable_av1": true
}
EOF
fi

rm -f "$tmp"

printf 'Wrote %s\n' "$flags"
if [ -f "$config" ]; then
	printf 'Updated %s\n' "$config"
fi

cat <<EOF

Launch the forked app from its desktop entry.  To open the Chromium GPU
diagnostics page, run:

  flatpak run --command=startvacuumtube $APP_ID --debug-gpu

EOF
