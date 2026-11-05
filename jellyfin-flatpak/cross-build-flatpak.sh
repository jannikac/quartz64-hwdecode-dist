#!/bin/sh
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
work=${WORK:-$here/cross-build-flatpak}
sysroot=$work/sysroot
stage=$work/stage/app
repo=$work/repo
dist=$work/dist
builddir=$work/flatpak-build
app_id=dev.jannik.JellyfinDesktopV4L2

: "${CROSS_CC:?run inside: nix-shell}"
: "${CROSS_CXX:?run inside: nix-shell}"
: "${CROSS_AR:?run inside: nix-shell}"
: "${CROSS_RANLIB:?run inside: nix-shell}"
: "${CROSS_STRIP:?run inside: nix-shell}"
: "${CROSS_LINUX_HEADERS:?run inside: nix-shell}"
: "${CROSS_PKG_CONFIG_PATH:?run inside: nix-shell}"
: "${QEMU_AARCH64:?run inside: nix-shell}"

cross_cc=$(command -v "$CROSS_CC")
cross_cxx=$(command -v "$CROSS_CXX")
cross_ar=$(command -v "$CROSS_AR")
cross_ranlib=$(command -v "$CROSS_RANLIB")
cross_strip=$(command -v "$CROSS_STRIP")
qemu=$(command -v "$QEMU_AARCH64")

apply_once() {
    if patch -p1 --dry-run -R -f < "$1" >/dev/null 2>&1; then
        printf 'already applied: %s\n' "$1"
    else
        patch -p1 -f < "$1"
    fi
}

for tool in flatpak curl git meson cmake ninja patch patchelf python3 gzip tar; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'missing required tool: %s\n' "$tool" >&2
        exit 1
    }
done

flatpak remote-add --user --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y --noninteractive --arch=aarch64 flathub \
    org.kde.Sdk//6.11 io.qt.qtwebengine.BaseApp//6.11 >/dev/null

sdk=$(find "$HOME/.local/share/flatpak/runtime/org.kde.Sdk/aarch64/6.11" \
    -maxdepth 3 -type d -name files | head -1)
base=$(find "$HOME/.local/share/flatpak/app/io.qt.qtwebengine.BaseApp/aarch64/6.11" \
    -maxdepth 3 -type d -name files | head -1)
[ -n "$sdk" ] && [ -n "$base" ] || {
    printf 'aarch64 SDK/base app not found\n' >&2
    exit 1
}

mkdir -p "$work" "$stage" "$dist"
rm -rf "$sysroot"
mkdir -p "$sysroot/usr/lib/aarch64-linux-gnu" "$sysroot/usr/share" \
    "$sysroot/app/lib/aarch64-linux-gnu"
ln -s "$sdk/include" "$sysroot/usr/include"
ln -s "$sdk/bin" "$sysroot/usr/bin"
ln -s "$sdk/libexec" "$sysroot/usr/libexec"
ln -s "$sdk/mkspecs" "$sysroot/usr/mkspecs"
ln -s "$sdk/lib/aarch64-linux-gnu/cmake" "$sysroot/usr/lib/aarch64-linux-gnu/cmake"
ln -s "$sdk/lib/aarch64-linux-gnu/pkgconfig" "$sysroot/usr/lib/aarch64-linux-gnu/pkgconfig"
ln -s "$sdk/share/pkgconfig" "$sysroot/usr/share/pkgconfig"
ln -s "$sdk/share/wayland-protocols" "$sysroot/usr/share/wayland-protocols"
ln -s "$sdk/share/ECM" "$sysroot/usr/share/ECM"

for f in "$sdk"/lib/*; do
    b=$(basename "$f")
    case "$b" in
        libc.so*|libm.so*|libmvec.so*|libpthread.so*|libdl.so*|librt.so*|libresolv.so*|libutil.so*|libanl.so*|ld-linux*|libgcc_s.so*|libstdc++.so*|*.a|crt*.o|*crt*.o|aarch64-linux-gnu) continue ;;
    esac
    ln -s "$f" "$sysroot/usr/lib/$b"
done
for f in "$sdk"/lib/aarch64-linux-gnu/*; do
    b=$(basename "$f")
    case "$b" in
        libc.so*|libm.so*|libmvec.so*|libpthread.so*|libdl.so*|librt.so*|libresolv.so*|libutil.so*|libanl.so*|ld-linux*|libgcc_s.so*|libstdc++.so*|*.a|crt*.o|*crt*.o|pkgconfig|cmake) continue ;;
    esac
    ln -s "$f" "$sysroot/usr/lib/aarch64-linux-gnu/$b"
done
ln -s "$base/include" "$sysroot/app/include"
ln -s "$base/bin" "$sysroot/app/bin" 2>/dev/null || true
for f in "$base"/lib/*; do
    b=$(basename "$f")
    case "$b" in
        aarch64-linux-gnu|libc.so*|libm.so*|libpthread.so*|libdl.so*|librt.so*|ld-linux*|libgcc_s.so*|libstdc++.so*|*.a|crt*.o|*crt*.o) continue ;;
    esac
    ln -s "$f" "$sysroot/app/lib/$b"
done
for f in "$base"/lib/aarch64-linux-gnu/*; do
    b=$(basename "$f")
    case "$b" in
        libc.so*|libm.so*|libpthread.so*|libdl.so*|librt.so*|ld-linux*|libgcc_s.so*|libstdc++.so*|*.a|crt*.o|*crt*.o|pkgconfig|cmake) continue ;;
    esac
    ln -s "$f" "$sysroot/app/lib/aarch64-linux-gnu/$b"
done
ln -s "$base/lib/aarch64-linux-gnu/cmake" "$sysroot/app/lib/aarch64-linux-gnu/cmake"
ln -s "$base/lib/aarch64-linux-gnu/pkgconfig" "$sysroot/app/lib/aarch64-linux-gnu/pkgconfig" 2>/dev/null || true

make_wrappers() {
    src=$1
    dest=$2
    rm -rf "$dest"
    mkdir -p "$dest"
    for f in "$src"/*; do
        [ -f "$f" ] && [ -x "$f" ] || continue
        b=$(basename "$f")
        cat > "$dest/$b" <<EOF
#!/bin/sh
exec "$qemu" -L "$sdk" -E "LD_LIBRARY_PATH=$sdk/lib/aarch64-linux-gnu:$sdk/lib" "$f" "\$@"
EOF
        chmod +x "$dest/$b"
    done
}
make_wrappers "$sdk/bin" "$sysroot/usr/bin"
make_wrappers "$sdk/libexec" "$sysroot/usr/libexec"
make_wrappers "$sdk/lib/libexec" "$sysroot/usr/lib/libexec"

libass_src=$work/libass-0.17.4
if [ ! -d "$libass_src" ]; then
    curl -L --fail -o "$work/libass-0.17.4.tar.gz" \
        https://github.com/libass/libass/releases/download/0.17.4/libass-0.17.4.tar.gz
    mkdir -p "$libass_src"
    tar -C "$libass_src" --strip-components=1 -xzf "$work/libass-0.17.4.tar.gz"
fi
cd "$libass_src"
env -u NIX_CFLAGS_COMPILE -u NIX_LDFLAGS \
    CC="$cross_cc" CXX="$cross_cxx" AR="$cross_ar" \
    RANLIB="$cross_ranlib" STRIP="$cross_strip" \
    PKG_CONFIG_PATH="$CROSS_PKG_CONFIG_PATH" PKG_CONFIG_LIBDIR="$CROSS_PKG_CONFIG_PATH" \
    ./configure --host=aarch64-unknown-linux-gnu --prefix=/app --libdir=/app/lib \
    --disable-static --enable-shared --enable-fontconfig --enable-asm \
    >"$work/libass-configure.log" 2>&1
make -j"${JOBS:-$(nproc)}" >"$work/libass-build.log" 2>&1
make install DESTDIR="$work/stage" >"$work/libass-install.log" 2>&1

libplacebo_src=$work/libplacebo-src
if [ ! -d "$libplacebo_src/.git" ]; then
    git clone --depth 1 --branch v7.351.0 --recurse-submodules \
        https://github.com/haasn/libplacebo.git "$libplacebo_src"
fi
cd "$libplacebo_src"
apply_once "$here/vulkan-python-xml.patch"
cat > "$work/cross.ini" <<EOF
[binaries]
c = '$cross_cc'
cpp = '$cross_cxx'
ar = '$cross_ar'
strip = '$cross_strip'
pkg-config = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'cortex-a55'
endian = 'little'

[properties]
needs_exe_wrapper = true
EOF
rm -rf "$work/libplacebo-build"
env -u NIX_CFLAGS_COMPILE -u NIX_LDFLAGS \
    PKG_CONFIG_SYSROOT_DIR="$sysroot" PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1 \
    PKG_CONFIG_ALLOW_SYSTEM_LIBS=1 \
    PKG_CONFIG_PATH="$sysroot/usr/lib/aarch64-linux-gnu/pkgconfig:$sysroot/usr/share/pkgconfig:$sysroot/app/lib/aarch64-linux-gnu/pkgconfig" \
    PKG_CONFIG_LIBDIR="$sysroot/usr/lib/aarch64-linux-gnu/pkgconfig:$sysroot/usr/share/pkgconfig:$sysroot/app/lib/aarch64-linux-gnu/pkgconfig" \
    meson setup "$work/libplacebo-build" . --cross-file="$work/cross.ini" \
    --prefix=/app --libdir=lib --buildtype=release \
    -Ddemos=false -Dtests=false -Dbench=false -Dfuzz=false \
    -Ddovi=disabled -Dlibdovi=disabled -Dvulkan=enabled -Dopengl=enabled \
    -Dshaderc=enabled -Dglslang=disabled -Dlcms=enabled \
    -Dunwind=disabled -Dxxhash=disabled >"$work/libplacebo-setup.log" 2>&1
env -u NIX_CFLAGS_COMPILE -u NIX_LDFLAGS ninja -C "$work/libplacebo-build" \
    >"$work/libplacebo-build.log" 2>&1
DESTDIR="$work/stage" ninja -C "$work/libplacebo-build" install \
    >"$work/libplacebo-install.log" 2>&1

WORK="$work/ffmpeg" "$here/cross-build-ffmpeg.sh" >"$work/ffmpeg-build.log" 2>&1
cp -a "$work/ffmpeg/stage/app/." "$stage"/

display_info_dir=$(PKG_CONFIG_PATH="$CROSS_PKG_CONFIG_PATH" \
    PKG_CONFIG_LIBDIR="$CROSS_PKG_CONFIG_PATH" \
    pkg-config --variable=libdir libdisplay-info)
rm -f "$stage"/lib/libdisplay-info.so*
cp -a "$display_info_dir"/libdisplay-info.so* "$stage/lib/"
chmod u+w "$stage"/lib/libdisplay-info.so*

pc=$work/pc
rm -rf "$pc"
mkdir -p "$pc"
for f in "$sysroot/usr/lib/aarch64-linux-gnu/pkgconfig"/*.pc \
         "$sysroot/usr/share/pkgconfig"/*.pc; do
    [ -f "$f" ] || continue
    sed "s|/usr|$sysroot/usr|g" "$f" > "$pc/$(basename "$f")"
done
for f in "$sysroot/app/lib/aarch64-linux-gnu/pkgconfig"/*.pc; do
    [ -f "$f" ] || continue
    sed "s|/app|$sysroot/app|g" "$f" > "$pc/$(basename "$f")"
done
for f in "$stage/lib/pkgconfig"/*.pc; do
    sed "s|/app|$stage|g" "$f" > "$pc/$(basename "$f")"
done

mpv_src=$work/mpv-0.41.0
if [ ! -f "$work/mpv-v0.41.0.tar.gz" ]; then
    curl -L --fail -o "$work/mpv-v0.41.0.tar.gz" \
        https://github.com/mpv-player/mpv/archive/refs/tags/v0.41.0.tar.gz
fi
rm -rf "$mpv_src"
mkdir -p "$mpv_src"
tar -C "$mpv_src" --strip-components=1 -xzf "$work/mpv-v0.41.0.tar.gz"
cd "$mpv_src"
apply_once "$here/patches/mpv/0001-mpv-v4l2request.patch"
rm -rf "$work/mpv-build"
env -u NIX_CFLAGS_COMPILE -u NIX_LDFLAGS \
    PKG_CONFIG_PATH="$pc:$CROSS_PKG_CONFIG_PATH" \
    PKG_CONFIG_LIBDIR="$pc:$CROSS_PKG_CONFIG_PATH" \
    meson setup "$work/mpv-build" . --cross-file="$work/cross.ini" \
    --prefix=/app --libdir=lib --buildtype=release \
    -Dlibmpv=true -Dv4l2request=enabled \
    -Dwayland=enabled -Ddrm=enabled -Dx11=disabled -Dgl-x11=disabled \
    -Dx11-clipboard=disabled -Dlua=disabled -Djavascript=disabled \
    -Duchardet=disabled -Dlibarchive=disabled -Djpeg=disabled \
    -Dalsa=disabled -Dpulse=enabled -Dpipewire=disabled -Djack=disabled \
    -Dopenal=disabled -Dcaca=disabled -Dsdl2-audio=disabled \
    -Dsdl2-video=disabled -Dsdl2-gamepad=disabled -Dvulkan=enabled \
    -Dgl=enabled -Degl=enabled -Dvaapi-drm=disabled -Dvaapi-x11=disabled \
    -Dvaapi-wayland=disabled -Dmanpage-build=disabled -Dhtml-build=disabled \
    -Dpdf-build=disabled \
    -Dc_link_args="-Wl,-rpath,/app/lib -L$sysroot/usr/lib/aarch64-linux-gnu -L$sysroot/usr/lib" \
    >"$work/mpv-setup.log" 2>&1
env -u NIX_CFLAGS_COMPILE -u NIX_LDFLAGS ninja -C "$work/mpv-build" \
    >"$work/mpv-build.log" 2>&1
DESTDIR="$work/stage" ninja -C "$work/mpv-build" install >"$work/mpv-install.log" 2>&1

mpvqt_src=$work/mpvqt-src
if [ ! -d "$mpvqt_src/.git" ]; then
    git clone https://invent.kde.org/libraries/mpvqt.git "$mpvqt_src"
fi
git -C "$mpvqt_src" checkout 2ebbd38bf65d01be9c55d673ecd43c8bb9a6fc8e

cat > "$work/toolchain.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_LIBRARY_ARCHITECTURE aarch64-linux-gnu)
set(CMAKE_C_COMPILER $cross_cc)
set(CMAKE_CXX_COMPILER $cross_cxx)
set(CMAKE_AR $cross_ar)
set(CMAKE_RANLIB $cross_ranlib)
set(CMAKE_STRIP $cross_strip)
set(CMAKE_CROSSCOMPILING_EMULATOR "$qemu;-L;$sdk;-E;LD_LIBRARY_PATH=$sdk/lib/aarch64-linux-gnu:$sdk/lib")
set(CMAKE_PREFIX_PATH "$sysroot/app;$sysroot/usr;$stage")
set(CMAKE_EXE_LINKER_FLAGS_INIT "-L$sysroot/usr/lib/aarch64-linux-gnu -L$sysroot/usr/lib -L$sysroot/app/lib/aarch64-linux-gnu -L$stage/lib -Wl,-rpath-link,$sysroot/usr/lib/aarch64-linux-gnu -Wl,-rpath-link,$sysroot/usr/lib -Wl,-rpath-link,$sysroot/app/lib/aarch64-linux-gnu -Wl,-rpath-link,$sysroot/app/lib -Wl,-rpath-link,$stage/lib -Wl,-rpath-link,$sysroot/usr/lib/aarch64-linux-gnu/pulseaudio")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-L$sysroot/usr/lib/aarch64-linux-gnu -L$sysroot/usr/lib -L$sysroot/app/lib/aarch64-linux-gnu -L$stage/lib -Wl,-rpath-link,$sysroot/usr/lib/aarch64-linux-gnu -Wl,-rpath-link,$sysroot/usr/lib -Wl,-rpath-link,$sysroot/app/lib/aarch64-linux-gnu -Wl,-rpath-link,$sysroot/app/lib -Wl,-rpath-link,$stage/lib -Wl,-rpath-link,$sysroot/usr/lib/aarch64-linux-gnu/pulseaudio")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
EOF

cd "$mpvqt_src"
rm -rf "$work/mpvqt-build"
env -u NIX_CFLAGS_COMPILE -u NIX_LDFLAGS \
    PKG_CONFIG_PATH="$pc:$CROSS_PKG_CONFIG_PATH" \
    PKG_CONFIG_LIBDIR="$pc:$CROSS_PKG_CONFIG_PATH" \
    cmake -S . -B "$work/mpvqt-build" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$(command -v ninja)" \
    -DCMAKE_TOOLCHAIN_FILE="$work/toolchain.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/app \
    -DQT_HOST_PATH="$sdk" -DQT_HOST_PATH_CMAKE_DIR="$sdk/lib/cmake" \
    -DQt6_DIR="$sysroot/usr/lib/aarch64-linux-gnu/cmake/Qt6" \
    -DLibmpv_INCLUDE_DIRS="$stage/include" \
    -DLibmpv_LIBRARIES="$stage/lib/libmpv.so" \
    -DBUILD_TESTING=OFF >"$work/mpvqt-configure.log" 2>&1
env -u NIX_CFLAGS_COMPILE -u NIX_LDFLAGS ninja -C "$work/mpvqt-build" \
    >"$work/mpvqt-build.log" 2>&1
DESTDIR="$work/stage" ninja -C "$work/mpvqt-build" install \
    >"$work/mpvqt-install.log" 2>&1

jmp_src=$work/jmp-src
if [ ! -d "$jmp_src/.git" ]; then
    git clone --depth 1 --branch v2.0.0 \
        https://github.com/jellyfin/jellyfin-media-player.git "$jmp_src"
fi
cd "$jmp_src"
apply_once "$here/patches/jellyfin-desktop/0001-jmp-v4l2request-reload.patch"
rm -rf "$work/jmp-build"
env -u NIX_CFLAGS_COMPILE -u NIX_LDFLAGS \
    PKG_CONFIG_PATH="$pc:$CROSS_PKG_CONFIG_PATH" \
    PKG_CONFIG_LIBDIR="$pc:$CROSS_PKG_CONFIG_PATH" \
    cmake -S . -B "$work/jmp-build" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$(command -v ninja)" \
    -DCMAKE_TOOLCHAIN_FILE="$work/toolchain.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/app \
    -DQT_HOST_PATH="$sdk" -DQT_HOST_PATH_CMAKE_DIR="$sdk/lib/cmake" \
    -DQt6_DIR="$sysroot/usr/lib/aarch64-linux-gnu/cmake/Qt6" \
    -DQT_ADDITIONAL_PACKAGES_PREFIX_PATH="$sysroot/app" \
    -DQt6WebEngineQuick_DIR="$sysroot/app/lib/aarch64-linux-gnu/cmake/Qt6WebEngineQuick" \
    -DQt6WebEngineCore_DIR="$sysroot/app/lib/aarch64-linux-gnu/cmake/Qt6WebEngineCore" \
    -DUSE_STATIC_MPVQT=OFF -DCMAKE_DISABLE_FIND_PACKAGE_X11=TRUE \
    -DMPV_INCLUDE_DIR="$stage/include" -DMPV_LIBRARY="$stage/lib/libmpv.so" \
    -DDL_LIBRARIES= -DICONV_LIBRARIES= -DBUILD_TESTING=OFF \
    >"$work/jmp-configure.log" 2>&1
env -u NIX_CFLAGS_COMPILE -u NIX_LDFLAGS ninja -C "$work/jmp-build" \
    >"$work/jmp-build.log" 2>&1
DESTDIR="$work/stage" ninja -C "$work/jmp-build" install >"$work/jmp-install.log" 2>&1

rm -rf "$builddir" "$repo"
flatpak build-init --arch=aarch64 --base=io.qt.qtwebengine.BaseApp \
    --base-version=6.11 "$builddir" "$app_id" \
    org.kde.Sdk//6.11 org.kde.Platform//6.11
cp -a "$stage/." "$builddir/files/"
rm -rf "$builddir/files/include" "$builddir/files/lib/pkgconfig" \
    "$builddir/files/lib/cmake" "$builddir/files/share/ffmpeg" \
    "$builddir/files/share/doc" "$builddir/files/share/fish" \
    "$builddir/files/share/zsh"
rm -f "$builddir/files"/lib/*.la \
    "$builddir/files/share/metainfo/mpv.metainfo.xml" \
    "$builddir/files/share/applications/mpv.desktop" \
    "$builddir/files/lib/libshaderc_shared.so"* \
    "$builddir/files/lib/libglslang.so"* \
    "$builddir/files/share/applications/org.jellyfin.JellyfinDesktop.desktop" \
    "$builddir/files/share/metainfo/org.jellyfin.JellyfinDesktop.appdata.xml"
install -Dm644 "$here/dev.jannik.JellyfinDesktopV4L2.desktop" \
    "$builddir/files/share/applications/$app_id.desktop"
cp "$builddir/files/share/icons/hicolor/scalable/apps/org.jellyfin.JellyfinDesktop.svg" \
    "$builddir/files/share/icons/hicolor/scalable/apps/$app_id.svg"
sed -i "s|^Icon=.*|Icon=$app_id|" "$builddir/files/share/applications/$app_id.desktop"
chmod +x "$builddir/files"/bin/*

for f in "$builddir/files"/bin/jellyfin-desktop \
         "$builddir/files"/bin/mpv "$builddir/files"/bin/ffmpeg \
         "$builddir/files"/bin/ffprobe; do
    chmod u+w "$f"
    patchelf --set-interpreter /lib/ld-linux-aarch64.so.1 \
        --set-rpath /app/lib "$f"
done
for f in "$builddir/files"/lib/libass.so.* \
         "$builddir/files"/lib/libavcodec.so.* \
         "$builddir/files"/lib/libavdevice.so.* \
         "$builddir/files"/lib/libavfilter.so.* \
         "$builddir/files"/lib/libavformat.so.* \
         "$builddir/files"/lib/libavutil.so.* \
         "$builddir/files"/lib/libdisplay-info.so.* \
         "$builddir/files"/lib/libMpvQt.so.* \
         "$builddir/files"/lib/libmpv.so.* \
         "$builddir/files"/lib/libplacebo.so.* \
         "$builddir/files"/lib/libswresample.so.* \
         "$builddir/files"/lib/libswscale.so.*; do
    if [ -f "$f" ]; then
        chmod u+w "$f"
        patchelf --set-rpath /app/lib "$f"
    fi
done

flatpak build-finish --command=jellyfin-desktop "$builddir" \
    --device=all --socket=wayland --socket=fallback-x11 --socket=pulseaudio \
    --share=ipc --share=network \
    --talk-name=org.freedesktop.ScreenSaver \
    --own-name=org.mpris.MediaPlayer2.JellyfinDesktop.* \
    --env=QML_DISABLE_DISK_CACHE=1
mkdir -p "$repo"
flatpak build-export --arch=aarch64 "$repo" "$builddir" stable
flatpak build-bundle --arch=aarch64 \
    --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
    "$repo" "$dist/$app_id.flatpak" "$app_id" stable
sha256sum "$dist/$app_id.flatpak" | tee "$dist/$app_id.flatpak.sha256"
