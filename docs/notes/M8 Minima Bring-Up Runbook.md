# M8 Minima Bring-Up Runbook

> This doc is mostly accurate (probably).  
> — Charles

Rev 1 boots unattended: eMMC `boot0` → SPL → TF-A → U-Boot → `bootflow scan` → Debian 13 (trixie) on the microSD card, Wi-Fi + Bluetooth up, SSH reachable. Ethernet doesn't work on rev 1; the cause is fixed in the current design files (see [Known issues](#known-issues-and-rev-2-changes)).

## Bring-up status (rev 1)

| Subsystem | Status | Evidence |
| --- | --- | --- |
| Power, PMIC (BD71847 @ I2C1 0x4B) | ✅ | `i2c probe` finds 0x4B; `bd718xx-pwrkey` registers in Linux |
| LPDDR4 4 GB, 2 ch / 2 rank @ 3000 MT/s | ✅ | mscale calibration + stress test pass; U-Boot and Linux report 4 GiB |
| UART2 console / UART4 | ✅ | `ttymxc1` / `ttymxc3`; UART4 needs the TF-A change below |
| eMMC (SD1, 8-bit) | ✅ | HS400 Enhanced Strobe in Linux; holds the bootloader in `boot0` |
| microSD (SD2, 4-bit) | ✅ | UHS SDR104 @ 208 MHz, so the 1.8 V VSELECT switch works |
| USB OTG1 (J901, device) | ✅ | SDP / fastboot via uuu |
| USB OTG2 → USB2514B hub | ✅ | Hub enumerates with 4 ports |
| PCIe → AX210 Wi-Fi | ✅ | Gen2 x1 link, `[8086:2725]`, firmware 89 loaded, `wlp1s0` |
| AX210 Bluetooth (USB, hub port 4) | ✅ | `hci0`, `ibt-0041-0041` firmware loaded |
| eMMC boot (`10\|10010\|0`) | ✅ | Boots without intervention |
| microSD boot ROM path (`10\|011X1\|0`) | ⚠️ Not tested | SD only tested as the OS medium, loaded by U-Boot |
| Ethernet (RTL8211F) | ❌ Rev 1 | PHY held in reset: `PHYRSTB` is a 3.3 V input driven from a 1.8 V pad; fixed in the design files for rev 2 |

## Board overview

| Function | Part | Note |
| --- | --- | --- |
| SoC | NXP i.MX8M Mini, MIMX8MM6DVTLZAA (quad Cortex-A53 + Cortex-M4) | |
| PMIC | ROHM BD71847AMWV-E2 | Same sequencing as NXP's 8MMINILPD4-EVK reference |
| DRAM | Micron MT53D1024M32D4DT-046, LPDDR4, 2 channel / 2 rank, 4 GB | Single BGA package, both channels/ranks inside |
| eMMC | BOM: Micron MTFC8GAMALBH-AAT, 8-bit, on SD1 | Rev 1 boards as built carry a **Samsung 32 GB** part (MID 0x15, `BJTD4R`). VCCQ hard-wired to 1.8 V |
| microSD | On SD2, 4-bit | VCCQ switchable 1.8/3.3 V via PMIC MUXSW, driven by `GPIO1_IO04` (USDHC2_VSELECT); no card-detect line |
| Ethernet PHY | Realtek RTL8211F-CG, RGMII | PHYAD = 1, 1.8 V RGMII I/O, TXDLY/RXDLY = 1 |
| USB hub | Microchip USB2514B | 4x downstream host ports, each behind a TPS2553 current limiter; reset on `GPIO5_IO11` |
| USB1 (J901) | Type-C, device-only | Used for the BootROM serial downloader |
| M.2 Key-E | PCIe x1 + USB 2.0 | Populated with an Intel AX210 |
| Debug console | CH342K USB-UART bridge | UART2 (`ttymxc1`) = console, UART4 (`ttymxc3`) = second login |
| Power in | USB-C PD via HUSB237 | Requests 9/12/15/20 V, selected by a switch; bucked down to 5V\_SYS by a TPS54560 |

## Where things live

| Path | What |
| --- | --- |
| `scripts/build-m8-minima.sh` | One-shot build: fetch sources + overlays, TF-A, U-Boot defconfig, `flash.bin` (copied to `bsp/`), kernel |
| `scripts/fetch-sources-m8-minima.sh` | Clones the upstream repos into `~` at their base commits and copies `bsp/modules/` over them |
| `scripts/package-m8-minima.sh` | Builds U-Boot and packages `flash.bin` (SPL + DDR firmware + TF-A + U-Boot) |
| `scripts/build-kernel-m8-minima.sh` | Builds kernel `Image`, modules and the board DTB |
| `scripts/build-sdcard-m8-minima.sh` | Builds the Debian SD card image (run with sudo) |
| `bsp/flash.bin` | Latest packaged bootloader |
| `bsp/uuu.exe` | NXP Universal Update Utility (Windows); not in git, download it (one-time setup step 4) |
| `bsp/emmc-bootloader.uuu` | uuu script: write `flash.bin` to eMMC `boot0` and enable eMMC boot |
| `bsp/ram-boot/` | uuu script + `Image` + DTB to boot a kernel from RAM over USB (no storage touched) |
| `bsp/kernel/m8-minima.config` | Kernel config fragment merged over `imx_v8_defconfig` |
| `bsp/ddr/` | RPA `.ds` script, calibrated `lpddr4_timing.c`, mscale log |
| `bsp/scale_ddr_tool_<ver>/` | mscale DDR tool, including the LPDDR4 training firmware used by the bootloader build; not in git, download it (one-time setup step 4) |
| `bsp/modules/<repo>/` | All source changes against upstream, at their repo paths; see `bsp/modules/README.md` for base commits |
| `docs/MIMX8MM6xxxLZ.mex` | Pin mux (MCUXpresso Config Tools); the source of truth for pin assignments |

## Host machine: Windows + WSL2 Ubuntu

What runs where:

- **Windows:** RPA spreadsheet (Excel), mscale DDR tool, `uuu.exe`, serial terminal, SD card flashing (Balena Etcher / Rufus).
- **WSL2 Ubuntu 20.04:** all cross-compiling and the rootfs build. Repos live in `~` on the native ext4 filesystem, not under `/mnt/c`.

### One-time setup

1. Toolchain and build dependencies (WSL):

   ```sh
   sudo apt install gcc-aarch64-linux-gnu gcc-10-aarch64-linux-gnu make bc bison flex \
       libssl-dev device-tree-compiler gnupg wget
   ```

2. Clone the four repos into `~` at the base commits listed in `bsp/modules/README.md`, then copy each `bsp/modules/<repo>/` folder over its repo. `scripts/fetch-sources-m8-minima.sh` does both (and `scripts/build-m8-minima.sh` runs it before every build):

   | Repo | Branch |
   | --- | --- |
   | `~/uboot-imx` ([nxp-imx/uboot-imx](https://github.com/nxp-imx/uboot-imx)) | `lf_v2026.04` |
   | `~/arm-trusted-firmware` ([ARM-software/arm-trusted-firmware](https://github.com/ARM-software/arm-trusted-firmware)) | `master` |
   | `~/imx-mkimage` ([nxp-imx/imx-mkimage](https://github.com/nxp-imx/imx-mkimage)) | `lf-6.18.20_2.0.0` (no changes) |
   | `~/linux-imx` ([nxp-imx/linux-imx](https://github.com/nxp-imx/linux-imx)) | `lf-6.18.y` (`--depth 1` is enough) |

3. Tools for the SD image, unpacked (not installed) under `~/tools`, because Ubuntu 20.04's debootstrap (1.0.118) and QEMU (4.2) are too old for trixie:

   ```sh
   mkdir -p ~/tools && cd ~/tools
   wget https://deb.debian.org/debian/pool/main/d/debootstrap/debootstrap_1.0.145_all.deb
   dpkg-deb -x debootstrap_1.0.145_all.deb debootstrap
   wget https://deb.debian.org/debian/pool/main/q/qemu/qemu-user_10.0.13+ds-0+deb13u1_amd64.deb
   dpkg-deb -x qemu-user_10.0.13+ds-0+deb13u1_amd64.deb qemu
   ```

4. NXP tools (Windows), downloaded into `bsp\` and ignored by git:

   - **uuu:** `uuu.exe` from the latest [mfgtools release](https://github.com/nxp-imx/mfgtools/releases/latest), saved as `bsp\uuu.exe`. The `.uuu` scripts need 1.2.39 or newer.
   - **mscale DDR tool:** the latest zip from [i.MX 8M Family DDR Tool Release](https://community.nxp.com/t5/i-MX-Processors-Knowledge-Base/i-MX-8-M-Family-DDR-Tool-Release/ta-p/1104467) (NXP login required), unpacked so its `bin\` folder sits at `bsp\scale_ddr_tool_<ver>\mscale_ddr_tool_<ver>\bin\` (v3.31 was used for rev 1). It's needed for the bootloader build, not just calibration: `package-m8-minima.sh` takes the LPDDR4 training firmware from the newest such `bin\` folder (override with `DDR_FW_DIR`). That folder must still contain the `DDR_FW_VER` version (`v201709`) the timing file was calibrated with.

5. Serial terminal (Windows): PuTTY or Tera Term on the CH342K's UART2 COM port, 115200 8N1. The terminal must be able to send a raw **Ctrl+C** (0x03); line-based serial monitors that send whole lines can't break U-Boot out of fastboot.

Run the scripts straight from the repo (CRLF-safe):

```sh
REPO="/mnt/c/My Drive/Ender Folder/Projects/crls design/M8 Minima"
tr -d '\r' < "$REPO/scripts/package-m8-minima.sh" | bash
```

## Pre-power checklist

- [ ] Visual inspection for solder bridges/tombstones around the PMIC (U301) and SoC BGA
- [ ] Check the DRAM/decoupling clusters (dozens of 0201/0402 caps) for shorts
- [ ] Confirm AGND / EXP-PAD nets aren't shorted to any rail
- [ ] Confirm boot-strap DIP switches SW402/SW403 are populated and in a defined position
- [ ] Confirm the DRAM ONOFF/TEST\_MODE switch SW401 is in the normal-operation position, not floating
- [ ] Set the PD voltage switch, and have a USB-C PD source that offers that voltage (not a plain 5 V-only charger)

## Power-on and rail verification

- [ ] `+VBUS` at J201 ≈ the voltage selected on the PD switch, after negotiation
- [ ] `+5V_SYS` at the TPS54560 output ≈ 5.0–5.2 V
- [ ] PMIC BUCK1..8 and LDO1/LDO2 sequence in the order of Table 1-3: SNVS rails first, then SOC/GPU/VPU/DRAM, then ARM, then the NVCC rails, then the SD mux, `POR_B` last
- [ ] `POR_B` releases high only once the full sequence completes
- [ ] If the sequence never gets past the SNVS stage, suspect a SoC/PMIC solder joint or an I2C1 short, not firmware

## Boot strap configuration (SW402/SW403)

| BOOT\_MODE\[1:0\] \| BOOT\_CFG \| TEST\_MODE | Result |
| --- | --- |
| 01\|XXXXX\|0 | USB1 OTG serial downloader: DDR calibration, uuu boots, flashing the eMMC |
| 10\|10010\|0 | Boot from SD1 (eMMC), 8-bit: **normal operation** |
| 10\|011X1\|0 | Boot from SD2 (microSD), 4-bit |
| 11\|XXXXX\|1 | JTAG / boundary-scan: production test only, mutually exclusive with normal boot |

## Step 1: DDR calibration (done)

Result for rev 1, in `bsp/ddr/`: 1D/2D training passes at 1500/200/50 MHz (3000 MT/s), 4096 MB detected across 2 chip selects, stress test passes at all three frequency points. `lpddr4_timing.c` is installed as `board/crls/m8_minima/lpddr4_timing.c` in U-Boot.

To redo it (new board revision, different DRAM):

1. Fill NXP's i.MX8M Mini Register Programming Aid (RPA) spreadsheet: the Device Information table (LPDDR4, 2 channel / 2 rank, MT53D1024M32D4DT-046, target frequency) and the BoardDataBusConfig worksheet (DQ/DQS/CA lane mapping straight from the schematic's byte-swap table; byte and bit swaps within a lane are fine, CA\[5:0\] swaps are not allowed). This produces the `.ds` script.
2. Strap `01|XXXXX|0`. Connect USB1 directly to the host PC (not through a hub) and open UART2.
3. Run the i.MX8MSCALE DDR Tool, load the `.ds` script, run calibration, then the stress test.
4. Copy the generated `lpddr4_timing.c` into the U-Boot board folder.

> **The training firmware version must match.** The tool's log shows which PHY training firmware it loaded (here `lpddr4_*_v201709.bin`). `package-m8-minima.sh` packages the same version from the tool's `bin/` folder (`DDR_FW_VER=v201709`). If you recalibrate with another version selected (e.g. `v202006`), build with `DDR_FW_VER=v202006`.

References (free NXP account required):

- [DDR Tool User Guide (Rev1)](https://community.nxp.com/pwmxy87654/attachments/pwmxy87654/blog/416/1/DDR%20Tool%20User%20Guide_Rev1.pdf)
- [i.MX8MSCALE DDR Tool User Guide](https://community.nxp.com/pwmxy87654/attachments/pwmxy87654/imx-processors@tkb/927/13/MSCALE_DDR_Tool_User_Guide.pdf)
- [DDR configuration and stress test on the i.MX8MM](https://community.nxp.com/t5/i-MX-Processors-Knowledge-Base/DDR-configuration-and-stress-test-on-the-i-MX8MM/ta-p/1749466)
- [i.MX8M (m850D) DDR Register Programming Aid (RPA)](https://community.nxp.com/t5/i-MX-Processors-Knowledge-Base/i-MX8M-m850D-DDR-Register-Programming-Aid-RPA/ta-p/1172441)
- [i.MX 8M Family DDR Tool Release](https://community.nxp.com/t5/i-MX-Processors-Knowledge-Base/i-MX-8-M-Family-DDR-Tool-Release/ta-p/1104467)
- [i.MX 8M Mini design resources (NXP)](https://www.nxp.com/design/design-center/development-boards-and-designs/8MMINILPD4-EVK)

## Step 2: Build the bootloader (`flash.bin`)

`flash.bin` = SPL + LPDDR4 training firmware + TF-A BL31 + U-Boot proper + DTB, packaged by `imx-mkimage`.

1. Build TF-A once (and again after changing it). The M8 Minima change gives UART4 to Linux instead of the Cortex-M4:

   ```sh
   make -C ~/arm-trusted-firmware PLAT=imx8mm CROSS_COMPILE=aarch64-linux-gnu- bl31
   ```

2. Build U-Boot and package:

   ```sh
   tr -d '\r' < "$REPO/scripts/package-m8-minima.sh" | bash
   cp ~/imx-mkimage/iMX8M/flash.bin "$REPO/bsp/flash.bin"
   ```

   The script builds U-Boot (`m8_minima_defconfig` must already be configured: `make ARCH=arm m8_minima_defconfig`), copies `u-boot-spl.bin`, `u-boot-nodtb.bin`, the board DTB, `bl31.bin`, U-Boot's `tools/mkimage` (as `mkimage_uboot`) and the DDR firmware into `imx-mkimage/iMX8M/`, then runs `make SOC=iMX8MM dtbs=imx8mm-m8-minima.dtb flash_evk_no_hdmi`. `ERROR: Could not find file tee.bin` in the log is harmless (OP-TEE is optional).

The U-Boot port is `board/crls/m8_minima/` + `configs/m8_minima_defconfig` + `include/configs/m8_minima.h`, derived from the 8MM EVK. Key board settings:

- DRAM map: 3 GB at `0x4000_0000` + 1 GB at `0x1_0000_0000` (`PHYS_SDRAM_SIZE` / `PHYS_SDRAM_2_SIZE`)
- Environment on eMMC (`mmc 0`) at 7 MiB; `boot_targets=mmc1 mmc0 usb0` (SD first)
- Display, NAND and EVK peripherals removed from the defconfig and DT

## Step 3: Boot over USB (serial downloader)

1. Strap `01|XXXXX|0`, connect J901 directly to the PC (not through a hub), open UART2.
2. From `bsp\` in PowerShell:

   ```powershell
   .\uuu.exe -b spl flash.bin
   ```

   Use `-b spl`. Plain `uuu flash.bin` only sends SPL and exits at `SDP: done`, leaving SPL waiting at `SDP: handle requests...` forever.
3. Expected on UART2: `U-Boot SPL`, `DDRINFO: DRAM rate 3000MTS`, `Trying to boot from USB SDP`, BL31 notices, then U-Boot with `DRAM: 4 GiB`.
4. After a USB boot, U-Boot automatically enters fastboot (`Detect USB boot. Will enter fastboot mode!`) and waits for uuu. Press **Ctrl+C** in the terminal to get `u-boot=>`.
5. Sanity checks:

   ```text
   bdinfo                 # two DRAM banks: 0x40000000/0xc0000000 + 0x100000000/0x40000000
   mmc list               # FSL_SDHC: 0 (eMMC), FSL_SDHC: 1 (SD)
   mmc dev 1; mmc info    # SD: UHS SDR104 (208MHz)
   i2c dev 0; i2c probe   # 4B (PMIC)
   ```

## Step 4: Build the kernel

```sh
tr -d '\r' < "$REPO/scripts/build-kernel-m8-minima.sh" | bash
```

- Base config: `imx_v8_defconfig` + `bsp/kernel/m8-minima.config` (BD718xx PMIC, PCIe host + PHY, iwlwifi/iwlmvm, btusb/btintel, compressed firmware loading). The script fails if any fragment option doesn't end up in `.config`.
- Board DT: the single source is `~/uboot-imx/dts/upstream/src/arm64/freescale/imx8mm-m8-minima.dts`, shared with U-Boot. The script copies it into the kernel tree, building it against **U-Boot's mainline** `imx8mm-evk.dtsi` (vendored as `imx8mm-m8-minima-evk-base.dtsi`). NXP's own `imx8mm-evk.dtsi` enables extra EVK audio/display hardware on pads this board uses differently.
- Output: `~/m8-minima-kernel/boot/{Image,imx8mm-m8-minima.dtb}` and `~/m8-minima-kernel/lib/modules/<version>/`. A first full build takes about 15–20 min.

Optional RAM-only test (nothing written to storage): copy `Image` and the DTB into `bsp\ram-boot\`, strap `01|XXXXX|0`, and from `bsp\ram-boot\` run `..\uuu.exe ram-boot.uuu`. The kernel boots up to `VFS: Unable to mount root fs` (no `root=`), which is enough to see PCIe, USB and MMC probe.

## Step 5: Build and flash the SD card image

```sh
tr -d '\r' < "$REPO/scripts/build-sdcard-m8-minima.sh" > /tmp/build-sdcard.sh
sudo bash /tmp/build-sdcard.sh
```

- Takes 20–40 min (the debootstrap second stage runs arm64 code under QEMU). Output: `~/m8-minima-sdcard.img` (3 GiB).
- Layout: `flash.bin` at 33 KiB; one ext4 root partition from 16 MiB, `PARTUUID=4d384d31-01`; `/boot/{Image,imx8mm-m8-minima.dtb,extlinux/extlinux.conf}`.
- Contents: Debian trixie arm64, kernel modules, `firmware-iwlwifi`, `wireless-regdb`, NetworkManager, wpa\_supplicant, hostapd, bluez, OpenSSH, serial logins on `ttymxc1` and `ttymxc3`. The root filesystem grows to fill the card on first boot.
- Login: `m8` / `m8minima`, changed at first login; root is locked.

Flash `\\wsl.localhost\Ubuntu\home\charles\m8-minima-sdcard.img` from Windows with Balena Etcher or Rufus.

To boot it while U-Boot is still loaded over USB: at `u-boot=>`, run `bootflow scan -lb`. U-Boot finds `/boot/extlinux/extlinux.conf` on `mmc1` and boots it.

## Step 6: Put the bootloader on the eMMC

1. Strap `01|XXXXX|0`, connect J901, power on.
2. From `bsp\`:

   ```powershell
   .\uuu.exe emmc-bootloader.uuu
   ```

   The script boots U-Boot over USB, downloads `flash.bin` via fastboot, writes it to eMMC **`boot0`** at sector 0x42 (33 KiB), reads it back and compares (`Total of N byte(s) were the same`), then runs `mmc partconf 0 1 1 0` (boot ACK on, boot from `boot0`, user-area access). The eMMC user area is not touched. Safe to re-run whenever `bsp\flash.bin` changes.
3. Optional check at `u-boot=>`: `mmc partconf 0` shows `BOOT_ACK: 0x1`, `BOOT_PARTITION_ENABLE: 0x1 (boot0)`, `PARTITION_ACCESS: 0x0 (user)`.
4. Power off, strap `10|10010|0`, unplug J901, keep the SD card in, power on. SPL prints `Trying to boot from MMC1`, U-Boot runs `bootflow scan`, Debian boots from SD.

`*** Warning - bad CRC, using default environment` at each boot is harmless; it goes away after the first `saveenv`.

## Day-to-day updates

| Change | How to deploy |
| --- | --- |
| Board DT only | Rebuild the DTB (`build-kernel-m8-minima.sh`, or `make freescale/imx8mm-m8-minima.dtb` after copying the DTS), then `scp imx8mm-m8-minima.dtb m8@<ip>:/tmp/` and `sudo cp /tmp/imx8mm-m8-minima.dtb /boot/` |
| Kernel | Copy `Image` to `/boot/` and `lib/modules/<version>` to `/usr/lib/modules/` on the board, the same way |
| U-Boot / TF-A | Rebuild `flash.bin` (step 2), copy it to `bsp\`, re-run step 6 |
| Everything | Rebuild the SD image (step 5) and reflash the card |

U-Boot reads the DTB from the SD card, not from `flash.bin`, so DT changes for Linux never need a bootloader reflash.

## Device tree notes

The board DTS starts from the 8MM EVK and removes or overrides everything this board doesn't have. Pin assignments follow `docs/MIMX8MM6xxxLZ.mex`.

- EVK hardware removed or disabled: HDMI bridge (ADV7535), MIPI DSI/CSI, LCDIF, audio codecs and SAI1/2/3, micfil, I2C2/I2C3 devices, Type-C controller, NAND (`gpmi`), IR receiver, backlight, LEDs.
- Ethernet: `phy-mode = "rgmii-id"` (delays from the PHY straps), PHY address 1, interrupt on `GPIO4_IO25` (SAI2\_TXC). Reset is on `GPIO5_IO21` (I2C4\_SDA), the **rev 2** pin; see Known issues.
- eMMC: `bus-width = 8`, fixed 1.8 V `vqmmc-supply` (dropped in U-Boot's dtsi, whose esdhc driver can't "set" a fixed regulator).
- microSD: `bus-width = 4`, `broken-cd`, VSELECT on `GPIO1_IO04`.
- USB: `usbotg1` peripheral-only; `usbotg2` host. Hub reset hog on `GPIO5_IO11`.
- PCIe: SoC-generated 100 MHz refclk (`fsl,refclk-pad-mode = OUTPUT`, `clocks = IMX8MM_CLK_PCIE1_PHY`), `fsl,clkreq-unsupported` (refclk free-running), PERST# on `GPIO5_IO13`, M.2 3.3 V modelled as always-on.
- M.2 radio enables: `W_DIS1_B` (`GPIO5_IO08`) and `W_DIS2_B` (`GPIO5_IO09`) hogged high.
- UART2/UART4: SDMA disabled (`dmas` removed). NXP's `sdma-imx7d.bin` isn't shipped, and without it UART4 floods the log.

> GPIO hogs use `GPIO_ACTIVE_LOW` + `output-low`, meaning "deasserted" (pin driven high). `output-high` on an active-low hog *asserts* it; that mistake held the USB hub in reset during bring-up.

## Peripheral verification (Linux)

Rev 1 results in brackets.

- [x] `free -h` shows \~4 GB [3.3 GiB available after CMA/reserved]
- [x] `lsblk`: `mmcblk0` eMMC (HS400ES), `mmcblk1` SD (SDR104)
- [x] `lsusb -t`: USB2514B hub with 4 ports, AX210 Bluetooth on port 4
- [x] `lspci`: `01:00.0` Intel AX210 `[8086:2725]`, link Gen2 x1
- [x] `dmesg | grep iwlwifi`: `loaded firmware version 89... ty-a0-gf-a0-89.ucode`
- [x] `bluetoothctl show`: Intel controller present
- [x] `nmcli dev wifi list` / connect: STA mode works, SSH over Wi-Fi
- [ ] `ethtool end0`: link up, PHY ID `001cc916` [blocked by PHYRSTB, rev 2]
- [ ] hostapd AP mode on the AX210
- [ ] Set the regulatory domain: `sudo iw reg set <country>`

## Known issues and rev 2 changes

### Ethernet PHY never leaves reset (rev 1, fixed in the design files)

Symptom: `Could not get PHY for FEC0: addr 1`; every MDIO address reads `0xffff`; the PHY's own 1.0 V rail (REG\_OUT/L601, C612/C613) is 0 V.

Cause: in the RTL8211F datasheet (Table 56 note), only the RGMII and MDC/MDIO/INTB pins follow DVDD\_RG; **`PHYRSTB` stays a 3.3 V input (Vih ≥ 2.0 V)**. Rev 1 drives it from `SAI2_TXFS` (NVCC\_SAI2 = 1.8 V) with R601 pulling up to 1.8 V, so the PHY stays in reset. Reset also gates the internal 1.0 V switching regulator (datasheet Figure 9), which explains the dead 1.0 V rail. Software polarity is correct (`gpio status gpio4_24` reads high).

No rework is planned for rev 1 boards; Ethernet stays unavailable on them. The current design files move `ENET_RST_B` to a 3.3 V pad with R601 pulling up to `+3.3V_BK6`, and the DT already uses the new pin.

### Rev 2 checklist

- [x] `ENET_RST_B` moved to **I2C4\_SDA (E13, `GPIO5_IO21`)** in the 3.3 V NVCC\_I2C bank; DT updated
- [x] R601 pulls up to `+3.3V_BK6`
- [ ] Power-on reset hold: with a plain pull-up the PHY leaves reset as soon as 3.3 V rises, short of the "≥ 10 ms low after power stable" rule (datasheet §7.17). U-Boot's 15 ms pulse covers it later; for a hardware guarantee use a pull-down instead (GPIO releases reset), or add about 4.7 µF from `PHYRSTB` to GND
- [ ] LED1/CFG\_LDO0 strap: 5.1 kΩ pull-down fights an LED + 2.49 kΩ to 3.3 V; confirm it samples low reliably (datasheet §7.9)
- [ ] Scope the 3.3 V rise time at the PHY: ≥ 0.5 ms required, < 0.1 ms "may cause permanent damage to the regulator" (Table 51)
- [ ] With external DVDD\_RG, the 1.8 V rail must rise with or before 3.3 V (Table 51, note 5); check the BUCK6/BUCK7 order
- [ ] Unroute B7 (ECSPI1\_MOSI, `GPIO5_IO07`) in the `.mex`; it's a no-connect on the schematic

Interfaces checked and fine at 1.8 V: RGMII data/clocks, MDC/MDIO (R603 pull-up to 1.8 V), INT\_B (open-drain, R602 to 1.8 V). PCIe TX/RX pairs are wired correctly (Gen2 link trains).

### Software fixes made during bring-up

| Problem | Fix | Where |
| --- | --- | --- |
| Linux crashed (`synchronous external abort` in `imx_uart_probe`) touching UART4 | Upstream TF-A's resource domain controller (RDC) config gives UART4 to the M4 only; changed to `D0R \| D0W` (A53) | `arm-trusted-firmware/plat/imx/imx8m/imx8mm/imx8mm_bl31_setup.c` |
| U-Boot reported 2 GiB | Second DRAM bank above 4 GB | `include/configs/m8_minima.h` |
| SD reported "no card present" | `broken-cd` (no CD line) | board DTS |
| eMMC `Setting to 1.8V error: -38` in U-Boot | Drop `vqmmc-supply` in the U-Boot dtsi only | `imx8mm-m8-minima-u-boot.dtsi` |
| USB hub held in reset | Hog polarity: `GPIO_ACTIVE_LOW` + `output-low` | board DTS |
| Ethernet reset/IRQ on wrong pins (`GPIO1_IO24/25`, which are RGMII pads) | Moved to the `.mex` pins | board DTS |
| UART4 DMA log flood | Remove `dmas` from UART2/UART4 | board DTS |
| `cfg80211: failed to load regulatory.db` | Install `wireless-regdb` | SD image package list |
| `emmc_dev=2` (EVK value) | `emmc_dev=0`; `boot_targets=mmc1 mmc0 usb0` | `m8_minima.env` |
| `imx-pgc-domain.4: Failed to add genpd provider` | Open: GPUMIX power domain, harmless on a headless board | — |

## Minecraft server

A quad Cortex-A53 is noticeably slower per core than the A72/A76 cores most "will this run Minecraft" write-ups assume (Raspberry Pi 4/5). Realistic target on this board: a small survival world, 2–4 players, modest render distance.

1. `apt install openjdk-21-jre-headless`
2. Use [PaperMC](https://papermc.io/downloads) ([source](https://github.com/PaperMC/Paper)) instead of the vanilla server jar: same Java Edition protocol, much better multithreaded tick performance on constrained hardware.
3. If Java Edition compatibility isn't required, [PocketMine-MP](https://github.com/pmmp/PocketMine-MP) (Bedrock protocol, PHP-based) is much lighter than a JVM.
4. Budget the JVM heap conservatively (`-Xmx2G` territory) and leave headroom for the OS and networking: about 3.3 GiB is available after kernel reservations.

## Wi-Fi access point (AX210)

STA mode is verified on this board. AP mode on the AX210 is inconsistently reported: Intel's forum says it's supported, but there are reports of it failing on non-2.4 GHz bands or getting stuck in a blocking state. Validate on the bench.

1. Driver, firmware and `wireless-regdb` are already in the image; set the country first: `sudo iw reg set <country>`.
2. `sudo apt install dnsmasq` (hostapd is already installed).
3. Configure hostapd for `wlp1s0`; test 2.4 GHz first, since that's the band with the most consistent community reports. Alternatively `nmcli dev wifi hotspot` for a quick test.
4. If AP mode proves unreliable, fall back to a module family NXP documents AP mode for on this SoC (88W8987/88W8997, e.g. Murata) as a second radio, or a USB Wi-Fi adapter on a hub port.

- [hostapd](https://w1.fi/hostapd/)
- [dnsmasq](https://thekelleys.org.uk/dnsmasq/)
- [Access Point Wi-Fi configuration on i.MX8 Family (NXP)](https://community.nxp.com/t5/Wireless-Connectivity-Knowledge/Access-Point-Wi-Fi-configuration-on-i-MX8-Family/ta-p/1438412)
- [UM11490 Feature Configuration Guide for NXP Wireless Modules](https://community.nxp.com/pwmxy87654/attachments/pwmxy87654/other/27476/1/UM11490%20Feature%20Configuration%20Guide%20for%20NXP-based%20Wireless%20Modules%20on%20i.MX%208M%20Quad%20EVK%20Running%20Linux.pdf)

## Gotchas and risk register

| Risk | Why it matters | Mitigation |
| --- | --- | --- |
| Non-PD or 5V-only charger on J201 | HUSB237 requests the switch-selected PD voltage before the buck steps down to 5V\_SYS; a source that can't supply it leaves the buck underpowered | Use a USB-C PD charger that offers the selected voltage; verify VBUS matches the switch before troubleshooting anything else |
| eMMC VCCQ hard-wired to 1.8 V | A wrong IO-voltage setting looks exactly like a dead eMMC | Fixed 1.8 V `vqmmc-supply` in the kernel DT; none in U-Boot's dtsi |
| SW401 (DRAM ONOFF/TEST\_MODE) left floating | Undefined DRAM test-pin state can look like a DDR training failure | Confirm the switch sits in the normal-operation position per the Micron datasheet |
| SW402/403 strapped to `11\|XXXXX\|1` | Boundary-scan mode, mutually exclusive with normal boot | Never leave in this position outside production test |
| `uuu flash.bin` without `-b spl` | Only SPL is sent; SPL waits at `SDP: handle requests...` forever | Always `uuu -b spl flash.bin` (or a script with the `SDPV:` stage) |
| U-Boot enters fastboot after every USB boot | Looks like a hang | Ctrl+C from a terminal that sends raw bytes (PuTTY/Tera Term) |
| DDR training firmware version mismatch | Timing file calibrated against a different PHY firmware may fail training | Package the version the mscale log shows (`DDR_FW_VER`) |
| TF-A RDC assigns UART4 to the M4 | Linux crashes probing UART4 | Keep the `imx8mm_bl31_setup.c` change when updating TF-A |
| EVK-derived DT leftovers | EVK devices on pins this board uses differently (wrong ENET pins, audio on boot straps, HDMI) | Check every enabled node against the `.mex` |
| Active-low GPIO hogs | `output-high` asserts an active-low line | Use `output-low` for "deasserted" |
| PHYRSTB is a 3.3 V input | 1.8 V reset never releases the PHY (rev 1) | Fixed in the design files: reset on a 3.3 V pad with a 3.3 V pull-up (see Known issues) |
| AX210 AP mode | Inconsistently reported working across kernel/driver versions | Validate on the bench; keep 88W8987 or a USB adapter as a fallback |
| Minecraft Java performance expectations | Quad Cortex-A53 is slower per-core than Pi 4/5 | Use PaperMC or Bedrock/PocketMine-MP; keep player count and render distance modest |
| Ubuntu 20.04 host tools vs. Debian trixie | Old debootstrap fails on the merged-`/usr` `base-files`; QEMU 4.2 breaks systemd-sysusers (`F_OFD_SETLK`) | Use debootstrap 1.0.145 and QEMU 10.0.13 from `~/tools` (host setup) |
| debootstrap and virtual packages | `network-manager`/`bluez` need `default-dbus-system-bus`, which debootstrap won't resolve | List `dbus` explicitly (already in the script) |
| Editing WSL files from Windows | Introduces CRLF line endings (seen in U-Boot's `arch/arm/dts/Makefile`) | Edit in WSL or normalise with `sed -i 's/\r$//'`; run repo scripts through `tr -d '\r'` |
| Source changes only in `~` | WSL files can be lost (copies of the scripts in `~` disappeared once) | Keep scripts in the repo; re-export changes to `bsp/modules/` and commit |
| WSL2 has no native access to physical disks | Can't `dd` straight to an SD card from inside WSL2 by default | Flash from Windows with Balena Etcher/Rufus, or `wsl --mount` the card |
| mscale DDR Tool and RPA are Windows-native | Won't run inside WSL2 | Run them directly on Windows |
| Building on /mnt/c/... inside WSL2 | 9p-mounted Windows drives are slow and can hit case-sensitivity issues | Keep build trees in WSL's `~` |
