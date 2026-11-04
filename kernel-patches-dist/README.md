# kernel-patches-dist — planned, not yet implemented

**Planned — not yet implemented.**

This directory will eventually package the kernel-side half of the Quartz64-B
V4L2 Request bring-up as an installable distro artifact.  The source material
currently lives in the board bring-up repository at:

```
/home/jannik/Development/quartz64-b-hvec-vp9-decoder-deepseek
```

Future scope:

- `patches/` and `linux/` kernel sources from SRC
- `DRIVER.md`
- `BRINGUP.md`
- `VP9-V4L2-DRIVER-SPEC.md`
- `boot-deploy/` (boot entries, initramfs hooks, and related boot files)

Nothing from those paths is copied here yet.  This pass deliberately covers
only the userland Flatpak and VA-API pieces.  The right packaging format for
the kernel artifact has not been chosen.
