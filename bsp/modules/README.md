# M8 Minima source overlays

Each folder holds the files added or modified on top of one upstream repo,
at the same relative paths. To recreate a build tree, clone the repo at the
listed commit and copy the folder's contents over it.

| Folder | Upstream | Branch | Base commit |
| --- | --- | --- | --- |
| `uboot-imx` | https://github.com/nxp-imx/uboot-imx.git | `lf_v2026.04` | `bb41975aeb4cbd153b49c9fd62da1d64cd65968d` |
| `arm-trusted-firmware` | https://github.com/ARM-software/arm-trusted-firmware.git | `master` | `d2a8287d34fa4571e6e68204f903ac8c2a43ed5d` |
| `linux-imx` | https://github.com/nxp-imx/linux-imx.git | `lf-6.18.y` | `6e694eda40aabd6671fca82b5416dbd76beeebb9` |

`imx-mkimage` (`lf-6.18.20_2.0.0`, `1b577853ae1afe1f26cdef27548da52fb424af48`)
needs no changes; `scripts/package-m8-minima.sh` stages its inputs.

`scripts/fetch-sources-m8-minima.sh` does this for all four repos (shallow
clones into `~`, overlays copied with CRLF stripped). The commits are pinned
there too, so update both places together. `scripts/build-m8-minima.sh` runs
it before building:

```sh
REPO="/mnt/c/My Drive/Ender Folder/Projects/crls design/M8 Minima"
tr -d '\r' < "$REPO/scripts/build-m8-minima.sh" | bash            # or: bash -s -- bootloader|kernel
```

Overlays win: re-running overwrites matching files in the clones, after
backing up any locally edited ones to `~/m8-minima-overlay-backup/<timestamp>/`.
Make edits in `bsp/modules/`, or copy changes made in a clone back there.

Notes:

- The board DTS is shared: `uboot-imx/dts/upstream/src/arm64/freescale/imx8mm-m8-minima.dts`
  is the one to edit. `scripts/build-kernel-m8-minima.sh` regenerates the two
  `linux-imx` DT files from it (plus U-Boot's mainline `imx8mm-evk.dtsi`), so
  the copies under `linux-imx/` are only a snapshot.
- `arm-trusted-firmware`: UART4 is assigned to the A53 domain instead of the M4
  (`imx8mm_bl31_setup.c`, RDC config).
- Host tools for the SD image (debootstrap 1.0.145, qemu-user 10.0.13) are not
  stored here; see the header of `scripts/build-sdcard-m8-minima.sh`.
