#!/usr/bin/env bash
# End-to-end board verification for the userland pieces in this repository.
#
# This script is intentionally destructive: it removes the old Alpine
# ffmpeg-v4l2/mpv-v4l2/jellyfin-desktop APKs and the old VacuumTube VA-API
# override before installing the new Flatpak/driver.  It never deletes the
# APK build outputs in /home/jannik/hwdecode-packages.
#
# It uses ordinary key-based SSH.  No password is stored in this repository.
# If the board requires a sudo password, the script asks for it interactively
# through SSH (`sudo -v`) and then uses the sudo credential cache.
#
# Usage:
#   BOARD=jannik@192.168.1.203 ./verify-userland.sh --yes
#
# Optional environment:
#   BOARD                       SSH target (default jannik@192.168.1.203)
#   SSH_OPTS                    extra options for ssh/scp
#   JELLYFIN_FLATPAK_BUNDLE     bundle to install
#   VA_DRIVER_SO                prebuilt v4l2_request_drv_video.so
#   TEST_FILE                   local VP9 file on the board for the mpv smoke test
#   JMP_WAIT_SECONDS            wait for JMP playback (default 180)
#   VAC_WAIT_SECONDS            wait for VacuumTube playback (default 180)
#   SKIP_JELLYFIN=1             do not install/check Jellyfin
#   SKIP_VACUUMTUBE=1           do not install/check VacuumTube

set -uo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
BOARD=${BOARD:-jannik@192.168.1.203}
SSH_OPTS=${SSH_OPTS:-}
APP_ID=dev.jannik.JellyfinDesktopV4L2
VAC_ID=rocks.shy.VacuumTube
REMOTE_TMP=${REMOTE_TMP:-/tmp/quartz64-hwdecode-dist}
JELLYFIN_FLATPAK_BUNDLE=${JELLYFIN_FLATPAK_BUNDLE:-$ROOT/jellyfin-flatpak/dist/dev.jannik.JellyfinDesktopV4L2.flatpak}
VA_DRIVER_SO=${VA_DRIVER_SO:-}
TEST_FILE=${TEST_FILE:-/home/jannik/test-claude/test.vp9.webm}
JMP_WAIT_SECONDS=${JMP_WAIT_SECONDS:-180}
VAC_WAIT_SECONDS=${VAC_WAIT_SECONDS:-180}
SKIP_JELLYFIN=${SKIP_JELLYFIN:-0}
SKIP_VACUUMTUBE=${SKIP_VACUUMTUBE:-0}
ASSUME_YES=0
WORK=$(mktemp -d "${TMPDIR:-/tmp}/quartz64-verify.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

if [ "${1:-}" = "--yes" ] || [ "${1:-}" = "-y" ]; then
    ASSUME_YES=1
elif [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    sed -n '2,40p' "$0"
    exit 0
elif [ $# -gt 0 ]; then
    echo "unknown argument: $1" >&2
    exit 2
fi

info() { printf '\n== %s ==\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }

remote() {
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "$BOARD" "$@"
}

sudo_run() {
    if ! remote 'sudo -n true' >/dev/null 2>&1; then
        echo "Board sudo requires a password; requesting an interactive sudo session..." >&2
        # shellcheck disable=SC2086
        ssh -t $SSH_OPTS "$BOARD" 'sudo -v' || return 1
    fi
    remote "sudo -n $*"
}

copy_tree() {
    local src=$1 dest=$2
    # shellcheck disable=SC2086
    tar -C "$src" -cf - . |
        ssh $SSH_OPTS "$BOARD" "rm -rf '$dest' && mkdir -p '$dest' && tar -C '$dest' -xf -"
}

copy_file() {
    local src=$1 dest=$2
    # shellcheck disable=SC2086
    scp $SSH_OPTS "$src" "$BOARD:$dest"
}

log_preflight() {
    local out=$ROOT/preflight-state.log
    {
        echo "# preflight-state.log generated $(date -u +%Y-%m-%dT%H:%M:%SZ) on the Quartz64-B"
        echo "# host: $(remote 'uname -srm' 2>&1)"
        echo
        echo "===== apk list --installed | grep -E ffmpeg-v4l2|mpv-v4l2|jellyfin-desktop ====="
        remote 'apk list --installed 2>/dev/null | grep -E "ffmpeg-v4l2|mpv-v4l2|jellyfin-desktop" || true'
        echo
        echo "===== flatpak list --user ====="
        remote 'flatpak list --user 2>&1 || true'
        echo
        echo "===== flatpak list (all installations) ====="
        remote 'flatpak list --columns=application,branch,origin,version,installation 2>&1 || true'
        echo
        echo "===== flatpak override --user --show $VAC_ID ====="
        remote "flatpak override --user --show $VAC_ID 2>&1 || true"
        echo
        echo "===== VacuumTube VA-API driver files ====="
        remote 'ls -l "$HOME"/.local/lib/v4l2-request-*/lib/dri/ 2>&1 || true'
        echo
        echo "===== free space ====="
        remote 'df -h / /home 2>&1'
    } > "$out" 2>&1
    echo "Wrote $out"
}

# ---------------------------------------------------------------------------
# Preflight: log state and make sure the replacement artifacts exist before
# anything destructive happens.
# ---------------------------------------------------------------------------
info "Preflight: logging current board state"
remote 'true' || die "cannot reach $BOARD over SSH"
log_preflight
cat "$ROOT/preflight-state.log"

if [ "$SKIP_JELLYFIN" != "1" ] && [ ! -f "$JELLYFIN_FLATPAK_BUNDLE" ]; then
    die "Jellyfin bundle not found: $JELLYFIN_FLATPAK_BUNDLE
Build it with jellyfin-flatpak/build-flatpak.sh, or set JELLYFIN_FLATPAK_BUNDLE,
or set SKIP_JELLYFIN=1 to verify only VacuumTube."
fi

if [ "$SKIP_VACUUMTUBE" != "1" ]; then
    [ -d "$ROOT/vacuumtube-vaapi/scripts" ] || die "vacuumtube-vaapi/scripts missing"
    if [ -z "$VA_DRIVER_SO" ]; then
        existing=$(remote 'ls -1t "$HOME"/.local/lib/v4l2-request-*/lib/dri/v4l2_request_drv_video.so 2>/dev/null | head -1' || true)
        if [ -n "$existing" ]; then
            echo "Preserving the currently installed VA-API driver before uninstall:"
            echo "  $existing"
            # shellcheck disable=SC2086
            scp $SSH_OPTS "$BOARD:$existing" "$WORK/v4l2_request_drv_video.so" ||
                die "could not copy the existing driver"
            VA_DRIVER_SO=$WORK/v4l2_request_drv_video.so
        else
            die "No VA-API driver found. Build one with
vacuumtube-vaapi/scripts/build-libva-cross.sh or build-libva-flatpak.sh,
or set VA_DRIVER_SO=/path/to/v4l2_request_drv_video.so,
or set SKIP_VACUUMTUBE=1 to verify only Jellyfin."
        fi
    fi
    [ -f "$VA_DRIVER_SO" ] || die "VA_DRIVER_SO is not a file: $VA_DRIVER_SO"
fi

if [ "$ASSUME_YES" != "1" ]; then
    cat <<EOF

This will DESTROY the current userland hardware-decode state on $BOARD:
  - remove APKs: jellyfin-desktop, mpv-v4l2, ffmpeg-v4l2
  - remove old Jellyfin/shim launchers and the old VacuumTube VA-API override
  - install: $JELLYFIN_FLATPAK_BUNDLE
  - install driver and configure $VAC_ID

It will NOT delete /home/jannik/hwdecode-packages/*.apk, the kernel, DTBs,
modules, bootloader, or the official Flathub apps.

Type "yes" to continue: 
EOF
    read -r answer
    [ "$answer" = "yes" ] || { echo "Aborted."; exit 1; }
fi

sudo_run 'true' || die "could not obtain sudo on $BOARD"

# ---------------------------------------------------------------------------
# 1. Remove the old Alpine userland packages and launchers.
# ---------------------------------------------------------------------------
info "Stopping old userland players / Flatpaks"
remote "pkill -f '/opt/jellyfin-desktop' 2>/dev/null || true
        pkill -f '/opt/mpv-v4l2' 2>/dev/null || true
        flatpak kill $APP_ID 2>/dev/null || true
        flatpak kill $VAC_ID 2>/dev/null || true"

info "Removing old APK packages (keeping /home/jannik/hwdecode-packages)"
sudo_run 'apk del jellyfin-desktop mpv-v4l2 ffmpeg-v4l2 2>&1 || true'

info "Removing old launchers, wrappers and desktop entries"
remote 'rm -f \
    "$HOME/.local/share/applications/jellyfin-desktop-v4l2.desktop" \
    "$HOME/Desktop/jellyfin-desktop-v4l2.desktop" \
    "$HOME/.local/share/applications/jellyfin-mpv-shim-v4l2.desktop" \
    "$HOME/Desktop/jellyfin-mpv-shim-v4l2.desktop" \
    "$HOME/.local/bin/jellyfin-mpv-shim-v4l2"
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    kbuildsycoca6 --noincremental 2>/dev/null || true'

# ---------------------------------------------------------------------------
# 2. Remove the old VacuumTube VA-API override and driver.
# ---------------------------------------------------------------------------
info "Copying the local VacuumTube script set to the board"
copy_tree "$ROOT/vacuumtube-vaapi" "$REMOTE_TMP/vacuumtube-vaapi" ||
    die "could not copy vacuumtube-vaapi to the board"
remote "chmod +x '$REMOTE_TMP/vacuumtube-vaapi/scripts/'*.sh"

if [ "$SKIP_VACUUMTUBE" != "1" ]; then
    info "Removing the old VacuumTube VA-API override"
    remote "'$REMOTE_TMP/vacuumtube-vaapi/scripts/uninstall-vacuumtube-v4l2.sh'" || true
fi
sudo_run 'rm -rf /opt/libva-v4l2-request'

# ---------------------------------------------------------------------------
# 3. Confirm the board is clean.
# ---------------------------------------------------------------------------
info "Confirming the old userland stack is gone"
clean_ok=1
old_apks=$(remote 'apk list --installed 2>/dev/null | grep -E "ffmpeg-v4l2|mpv-v4l2|jellyfin-desktop" || true')
if [ -n "$old_apks" ]; then
    echo "Still installed:"; echo "$old_apks"; clean_ok=0
fi
old_ov=$(remote "flatpak override --user --show $VAC_ID 2>/dev/null || true" | grep -E 'LIBVA_|v4l2-request' || true)
if [ -n "$old_ov" ]; then
    echo "Old VacuumTube override entries remain:"; echo "$old_ov"; clean_ok=0
fi
[ "$clean_ok" -eq 1 ] && echo "Clean: no old APKs and no old LIBVA overrides."

# ---------------------------------------------------------------------------
# 4a. Install the new Jellyfin Flatpak bundle.
# ---------------------------------------------------------------------------
jmp_result="SKIPPED"
if [ "$SKIP_JELLYFIN" != "1" ]; then
    info "Installing the Jellyfin Flatpak bundle"
    copy_file "$JELLYFIN_FLATPAK_BUNDLE" "$REMOTE_TMP/dev.jannik.JellyfinDesktopV4L2.flatpak" ||
        die "could not copy the Flatpak bundle"
    if remote "flatpak install --user --noninteractive --reinstall '$REMOTE_TMP/dev.jannik.JellyfinDesktopV4L2.flatpak'"; then
        jmp_result="INSTALLED"
    else
        jmp_result="INSTALL_FAILED"
        warn "Flatpak install failed; leaving the board in this state for diagnosis"
    fi
fi

# ---------------------------------------------------------------------------
# 4b. Install the VacuumTube driver and configuration.
# ---------------------------------------------------------------------------
vac_result="SKIPPED"
if [ "$SKIP_VACUUMTUBE" != "1" ]; then
    info "Installing the VacuumTube VA-API driver and override"
    copy_file "$VA_DRIVER_SO" "$REMOTE_TMP/v4l2_request_drv_video.so" ||
        die "could not copy the VA-API driver"
    if remote "cd '$REMOTE_TMP/vacuumtube-vaapi' && ./scripts/install-driver-override.sh '$REMOTE_TMP/v4l2_request_drv_video.so'"; then
        remote "cd '$REMOTE_TMP/vacuumtube-vaapi' && ./scripts/configure-vacuumtube.sh" ||
            warn "configure-vacuumtube.sh failed; the driver override may still be usable"
        vac_result="INSTALLED"
    else
        vac_result="INSTALL_FAILED"
        warn "VA-API driver install failed; leaving the board in this state for diagnosis"
    fi
fi

# ---------------------------------------------------------------------------
# 5a. Jellyfin checks: packaged mpv smoke test, then live JMP state.
# ---------------------------------------------------------------------------
if [ "$jmp_result" = "INSTALLED" ]; then
    jmp_result="FAIL"
    copy_tree "$ROOT/jellyfin-flatpak/scripts" "$REMOTE_TMP/jellyfin-flatpak/scripts" ||
        die "could not copy the Jellyfin check scripts to the board"
    info "Jellyfin: packaged mpv/FFmpeg local-file smoke test"
    test_file_ok=$(remote "[ -f '$TEST_FILE' ] && echo yes || echo no")
    if [ "$test_file_ok" = "yes" ]; then
        if remote "'$REMOTE_TMP/jellyfin-flatpak/scripts/test-flatpak-mpv.sh' '$TEST_FILE'"; then
            echo "Packaged mpv/FFmpeg hardware decode: PASS"
        else
            echo "Packaged mpv/FFmpeg hardware decode: FAIL"
        fi
    else
        warn "test file not found on board: $TEST_FILE (skipping mpv smoke test)"
    fi

    info "Jellyfin: live JMP hwdec check"
    remote "mkdir -p \"\$HOME/.var/app/$APP_ID/cache\""
    if ! remote "pgrep -f '/app/bin/jellyfin-desktop' >/dev/null"; then
        echo "Starting Jellyfin Desktop (app ID $APP_ID)..."
        remote "setsid env XDG_RUNTIME_DIR=/run/user/\$(id -u) WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus flatpak run $APP_ID >/tmp/jmp-verify.log 2>&1 < /dev/null &" || true
    fi
    cat <<EOF
Log in to your own Jellyfin account in the JMP window, enable hardware
decoding in Client Settings, and start any video.  Waiting up to ${JMP_WAIT_SECONDS}s
for a playing v4l2request stream.  The check reads only hwdec/player state and
process maps; it does not read titles, paths, or URLs.
EOF
    deadline=$(( $(date +%s) + JMP_WAIT_SECONDS ))
    last_out=""
    while [ "$(date +%s)" -lt "$deadline" ]; do
        last_out=$(remote "HOME='$HOME' sh '$REMOTE_TMP/jellyfin-flatpak/scripts/check_jmp_hw.sh' 2>&1" || true)
        if printf '%s\n' "$last_out" | grep -q 'hwdec-current = v4l2request' &&
           printf '%s\n' "$last_out" | grep -q 'rkvdec_irq_delta_5s = [1-9]'; then
            echo "$last_out"
            jmp_result="PASS"
            break
        fi
        sleep 10
    done
    if [ "$jmp_result" != "PASS" ]; then
        echo "$last_out"
        warn "JMP did not reach a verified playing v4l2request state within ${JMP_WAIT_SECONDS}s"
        warn "Log: /tmp/jmp-verify.log on the board"
        jmp_result="FAIL"
    fi
fi

# ---------------------------------------------------------------------------
# 5b. VacuumTube check.
# ---------------------------------------------------------------------------
if [ "$vac_result" = "INSTALLED" ]; then
    vac_result="FAIL"
    info "VacuumTube: live VA-API / rkvdec check"
    if ! remote "flatpak ps --columns=application 2>/dev/null | grep -qx '$VAC_ID'"; then
        echo "Starting $VAC_ID..."
        remote "setsid env XDG_RUNTIME_DIR=/run/user/\$(id -u) WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus flatpak run $VAC_ID >/tmp/vacuumtube-verify.log 2>&1 < /dev/null &" || true
    fi
    cat <<EOF
Play a VP9 video in VacuumTube.  Waiting up to ${VAC_WAIT_SECONDS}s for the
driver to be mapped, the rkvdec node to be held, and the IRQ counter to move.
EOF
    deadline=$(( $(date +%s) + VAC_WAIT_SECONDS ))
    last_out=""
    while [ "$(date +%s)" -lt "$deadline" ]; do
        last_out=$(remote "cd '$REMOTE_TMP/vacuumtube-vaapi' && ./scripts/check-vacuumtube-hw.sh 2>&1" || true)
        if printf '%s\n' "$last_out" | grep -q '^PASS: driver mapped'; then
            echo "$last_out"
            vac_result="PASS"
            break
        fi
        sleep 10
    done
    if [ "$vac_result" != "PASS" ]; then
        echo "$last_out"
        warn "VacuumTube did not reach a verified playing VA-API state within ${VAC_WAIT_SECONDS}s"
        warn "Log: /tmp/vacuumtube-verify.log on the board"
        vac_result="FAIL"
    fi
fi

# ---------------------------------------------------------------------------
# 6. Report.
# ---------------------------------------------------------------------------
info "Result"
printf 'Jellyfin Desktop (%s): %s\n' "$APP_ID" "$jmp_result"
printf 'VacuumTube (%s): %s\n' "$VAC_ID" "$vac_result"
if [ "$clean_ok" -ne 1 ]; then
    printf 'Pre-install clean check: FAIL (old state still present)\n'
fi

if [ "$jmp_result" = "FAIL" ] || [ "$vac_result" = "FAIL" ] ||
   [ "$jmp_result" = "INSTALL_FAILED" ] || [ "$vac_result" = "INSTALL_FAILED" ] ||
   [ "$clean_ok" -ne 1 ]; then
    cat <<EOF

Diagnostics left in place; no further uninstall was attempted.
Useful board commands:
  flatpak ps --columns=application,pid,child-pid
  cat /tmp/jmp-verify.log
  cat /tmp/vacuumtube-verify.log
  grep -i rkvdec /proc/interrupts
  cat $ROOT/preflight-state.log   # captured before the destructive step
EOF
    exit 1
fi

exit 0
