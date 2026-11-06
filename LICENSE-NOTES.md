# License notes

This repository is a set of personal build recipes and patches, not a
standalone licensed work.  The components it builds keep their upstream
licenses:

| Component | Upstream license | Notes |
|---|---|---|
| FFmpeg | LGPL-2.1-or-later by default; GPL-2.0-or-later / GPL-3.0-or-later when built with `--enable-gpl --enable-version3` | The manifest enables GPL and version 3, so the resulting FFmpeg libraries are GPL-3.0-or-later. |
| mpv / libmpv | GPL-2.0-or-later (or LGPL-2.1-or-later in some configurations) | The manifest keeps the GPL build and links the GPL FFmpeg. |
| jellyfin-media-player / Jellyfin Desktop | GPL-2.0-or-later | Built from the pinned v2.0.0 source. |
| libplacebo | LGPL-2.1-or-later | Used by mpv's `gpu-next` renderer. |
| libass | ISC | Subtitle renderer. |
| libva-v4l2-request fork | MIT (upstream libva-v4l2-request) | Patched VA-API driver; see the fork and patch headers. |
| VacuumTube | MIT | The personal `dev.jannik.VacuumTubeV4L2` fork builds the pinned upstream v2.0.1 source.  The upstream MIT text is kept in `vacuumtube-flatpak/LICENSE`.  Credit goes to the upstream author, shy. |

Because the Flatpak bundles GPL FFmpeg/mpv/JMP code, a **Flathub submission is
out of scope**: Flathub has its own licensing, source-availability, sandbox,
and review requirements.  This is a personal/sideloaded build.

The `vacuumtube-flatpak/` fork is a personal packaging of MIT-licensed
VacuumTube 2.0.1.  It is not affiliated with or endorsed by the upstream
VacuumTube project or its Flathub listing.  Upstream source and license:
<https://github.com/shy1132/VacuumTube>.

If you redistribute a bundle built from this repository, you are responsible
for providing the corresponding source for the GPL components and for complying
with the other upstream licenses.  The pins in `jellyfin-flatpak/README.md` and
`vacuumtube-flatpak/README.md` identify the exact sources used.
