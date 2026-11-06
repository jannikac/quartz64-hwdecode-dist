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
    cpio
    curl
    dtc
    file
    flex
    git
    gnumake
    kmod
    patch
    perl
    pkg-config
    python3
    wget
    xz
    zstd

    # aarch64 target toolchain and libraries used by the standalone FFmpeg
    # hardware test.  The JMP Flatpak itself is built from its manifest.
    cross.stdenv.cc
    cross.linuxHeaders
    cross.zlib
    cross.openssl
    cross.libdrm
    cross.udev

    # Host-side manifest build.  qemu-aarch64 is registered as a sandboxed
    # binfmt_misc handler inside an unprivileged user namespace.
    flatpak-builder
    util-linux
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
            zlib openssl libdrm udev
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
    echo "The JMP Flatpak is built from its manifest by"
    echo "jellyfin-flatpak/build-flatpak.sh; see jellyfin-flatpak/README.md."
  '';
}
