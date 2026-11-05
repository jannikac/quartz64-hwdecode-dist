let
  # Use the host's nixpkgs channel so the aarch64 cross toolchain comes from
  # the binary cache.  Nothing is installed into a profile.  For a fully
  # reproducible shell, override NIX_PATH with a pinned nixpkgs checkout:
  #
  #   NIX_PATH=nixpkgs=/path/to/nixpkgs nix-shell
  pkgs = import <nixpkgs> {};

  cross = pkgs.pkgsCross.aarch64-multiplatform;
in
pkgs.mkShell {
  packages = with pkgs; [
    # Host build tools
    bc
    bison
    ccache
    cmake
    cpio
    curl
    dtc
    file
    flex
    git
    gnumake
    kmod
    meson
    ninja
    patch
    patchelf
    perl
    pkg-config
    python3
    wayland-scanner
    wget
    xz
    zstd

    # aarch64 target toolchain and libraries used by the FFmpeg, libass and
    # mpv cross builds.  Qt comes from the aarch64 Flatpak SDK.
    cross.stdenv.cc
    cross.linuxHeaders
    cross.zlib
    cross.libdrm
    cross.udev
    cross.wayland
    cross.wayland-protocols
    cross.fribidi
    cross.freetype
    cross.fontconfig
    cross.harfbuzz
    cross.libdisplay-info
    cross.vulkan-headers

    # Runs aarch64 host tools such as moc/qmlcachegen when cross-building JMP
    qemu
  ];

  shellHook = ''
    export CROSS_CC=aarch64-unknown-linux-gnu-gcc
    export CROSS_CXX=aarch64-unknown-linux-gnu-g++
    export CROSS_AR=aarch64-unknown-linux-gnu-ar
    export CROSS_RANLIB=aarch64-unknown-linux-gnu-ranlib
    export CROSS_STRIP=aarch64-unknown-linux-gnu-strip
    export CROSS_PKG_CONFIG=pkg-config
    export CROSS_LINUX_HEADERS=${cross.linuxHeaders}
    # Keep target .pc files separate from the native shell's PKG_CONFIG_PATH.
    export CROSS_PKG_CONFIG_PATH=${
      let deps = map pkgs.lib.getDev (with cross; [
            zlib libdrm udev wayland fribidi freetype fontconfig harfbuzz
            libdisplay-info wayland-protocols vulkan-headers
          ]);
      in "${pkgs.lib.makeSearchPath "lib/pkgconfig" deps}:${pkgs.lib.makeSearchPath "share/pkgconfig" deps}"
    }
    export QEMU_AARCH64=qemu-aarch64

    echo "Quartz64-B cross shell"
    echo "  CC:        $CROSS_CC"
    echo "  CXX:       $CROSS_CXX"
    echo "  qemu:      $(command -v $QEMU_AARCH64 || true)"
    echo
    echo "Target dependencies are provided by pkgsCross.aarch64-multiplatform."
    echo "The Flatpak cross build downloads the aarch64 SDK/base runtimes with"
    echo "flatpak; see jellyfin-flatpak/README.md."
  '';
}
