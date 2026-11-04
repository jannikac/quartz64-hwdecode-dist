#!/bin/sh
# Query only safe mpv/JMP state and process maps while the patched Flatpak
# build is playing.  It never asks for media-title, path, a stream URL, or
# any Jellyfin account data.
#
# The JMP patch puts the IPC socket under Qt's GenericCacheLocation.  Inside
# the Flatpak that is ~/.var/app/<app-id>/cache, which is the app's own
# host-backed writable directory (not the sandbox-private /tmp).

APP_ID=${JMP_APP_ID:-dev.jannik.JellyfinDesktopV4L2}
SOCK=${JMP_IPC_SOCK:-$HOME/.var/app/$APP_ID/cache/jmp-video.sock}
PID=$(pgrep -f '/app/bin/jellyfin-desktop' | head -1)

echo "PID=$PID"
echo "SOCK=$SOCK"
if [ -z "$PID" ]; then
    echo "FAIL: jellyfin-desktop is not running"
    exit 1
fi
if [ ! -S "$SOCK" ]; then
    alt=$(find "$HOME/.var/app/$APP_ID/cache" -name jmp-video.sock -type s 2>/dev/null | head -1)
    [ -n "$alt" ] && SOCK=$alt
fi
ls -l "$SOCK" 2>&1

echo ====MAPS====
map_fail=0
for p in $(grep -E 'libav(codec|format|util|filter)|libmpv' "/proc/$PID/maps" 2>/dev/null |
           awk '{print $6}' | sort -u); do
    case "$p" in
        /app/*|*dev.jannik.JellyfinDesktopV4L2*)
            echo "ok   $p"
            ;;
        *)
            echo "FAIL unexpected host/non-Flatpak library: $p"
            map_fail=1
            ;;
    esac
done
[ "$map_fail" -eq 0 ] || echo "FAIL: the process mapped FFmpeg/mpv from outside the Flatpak"

python3 - "$SOCK" "$PID" <<'PY'
import json, os, socket, sys, time
sock_path, pid_s = sys.argv[1], sys.argv[2]
pid = int(pid_s)
failed = False

def q(name, i):
    s = socket.socket(socket.AF_UNIX)
    s.connect(sock_path)
    s.settimeout(3)
    s.sendall((json.dumps({"command": ["get_property", name], "request_id": i}) + "\n").encode())
    buf = b""
    while True:
        d = s.recv(4096)
        if not d:
            return None
        buf += d
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get("request_id") == i:
                s.close()
                return o.get("data")

props = ["idle-active", "pause", "video-codec", "hwdec", "hwdec-current",
         "hwdec-interop", "current-vo", "width", "height", "time-pos",
         "duration", "estimated-vf-fps", "frame-drop-count",
         "decoder-frame-drop-count"]
values = {}
for i, name in enumerate(props, 1):
    values[name] = q(name, i)
    print(name, "=", values[name])

if values.get("hwdec-current") != "v4l2request":
    print("FAIL: hwdec-current is not v4l2request")
    failed = True
if values.get("idle-active") is not False:
    print("FAIL: player is idle (nothing is playing)")
    failed = True

clk = os.sysconf("SC_CLK_TCK")
def ticks():
    with open(f"/proc/{pid}/stat") as f:
        p = f.read().split()
    return int(p[13]) + int(p[14])
def total():
    with open("/proc/stat") as f:
        p = f.readline().split()
    return sum(int(x) for x in p[1:])
def irq_sum():
    try:
        with open("/proc/interrupts") as f:
            lines = [l for l in f if "rkvdec" in l.lower()]
    except OSError:
        return None
    total = 0
    for line in lines:
        for field in line.split()[1:]:
            if field.isdigit():
                total += int(field)
    return total

m0, t0, i0, w0 = ticks(), total(), irq_sum(), time.monotonic()
time.sleep(5)
m1, t1, i1, w1 = ticks(), total(), irq_sum(), time.monotonic()
elapsed = w1 - w0
print("jmp_cpu_pct_one_core = %.1f" % ((m1 - m0) / (elapsed * clk) * 100))
if t1 > t0:
    print("jmp_cpu_pct_machine = %.1f" % ((m1 - m0) / (t1 - t0) * 100))
if i0 is None or i1 is None:
    print("FAIL: no rkvdec line in /proc/interrupts")
    failed = True
else:
    print("rkvdec_irq_delta_5s = %d" % (i1 - i0))
    if i1 <= i0:
        print("FAIL: rkvdec IRQ counter did not increase")
        failed = True

sys.exit(1 if failed else 0)
PY
rc=$?
[ "$map_fail" -eq 0 ] || rc=1
exit "$rc"
