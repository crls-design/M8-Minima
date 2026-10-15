#!/usr/bin/env bash
set -Eeuo pipefail

UBOOT_DIR="${UBOOT_DIR:-$HOME/uboot-imx}"
MKIMAGE_DIR="${MKIMAGE_DIR:-$HOME/imx-mkimage}"
REPO_DIR="${REPO_DIR:-/mnt/c/My Drive/Ender Folder/Projects/crls design/M8 Minima}"
# LPDDR4 PHY training firmware, from the mscale DDR tool unpacked under bsp/
# (not in git; newest version wins). Must be the same version the tool used
# when it generated lpddr4_timing.c (see bsp/ddr/mscale log.txt).
DDR_FW_DIR="${DDR_FW_DIR:-$(ls -d "$REPO_DIR"/bsp/scale_ddr_tool_*/mscale_ddr_tool_*/bin 2>/dev/null | sort -V | tail -n 1 || true)}"
DDR_FW_VER="${DDR_FW_VER:-v201709}"
DTB="${DTB:-imx8mm-m8-minima.dtb}"
ATF_DIR="${ATF_DIR:-$HOME/arm-trusted-firmware}"
BL31="${BL31:-$ATF_DIR/build/imx8mm/release/bl31.bin}"

CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
CC="${CC:-aarch64-linux-gnu-gcc-10}"
JOBS="${JOBS:-$(nproc)}"

die() {
	echo "error: $*" >&2
	exit 1
}

need_file() {
	[[ -f "$1" ]] || die "missing file: $1"
}

need_dir() {
	[[ -d "$1" ]] || die "missing directory: $1"
}

need_command() {
	command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

need_command make
need_command aarch64-linux-gnu-ld
need_command aarch64-linux-gnu-objcopy
need_dir "$UBOOT_DIR"
need_dir "$MKIMAGE_DIR/iMX8M"
need_dir "$ATF_DIR"
[[ -n "$DDR_FW_DIR" ]] ||
	die "mscale DDR tool not found under $REPO_DIR/bsp; download and unpack it there (see the bring-up runbook) or set DDR_FW_DIR"
need_dir "$DDR_FW_DIR"

if [[ ! -f "$BL31" ]]; then
	echo "Building Arm Trusted Firmware BL31"
	make -C "$ATF_DIR" -j"$JOBS" \
		PLAT=imx8mm \
		CROSS_COMPILE="$CROSS_COMPILE" \
		bl31
fi

need_file "$BL31"

# mscale tool name -> name imx-mkimage expects
declare -A DDR_FW=(
	[lpddr4_imem_1d_$DDR_FW_VER.bin]=lpddr4_pmu_train_1d_imem.bin
	[lpddr4_dmem_1d_$DDR_FW_VER.bin]=lpddr4_pmu_train_1d_dmem.bin
	[lpddr4_imem_2d_$DDR_FW_VER.bin]=lpddr4_pmu_train_2d_imem.bin
	[lpddr4_dmem_2d_$DDR_FW_VER.bin]=lpddr4_pmu_train_2d_dmem.bin
)
for firmware in "${!DDR_FW[@]}"; do
	need_file "$DDR_FW_DIR/$firmware"
done

echo "Building M8 Minima U-Boot"
make -C "$UBOOT_DIR" -j"$JOBS" \
	ARCH=arm \
	CROSS_COMPILE="$CROSS_COMPILE" \
	CC="$CC"

need_file "$UBOOT_DIR/arch/arm/dts/$DTB"

echo "Preparing imx-mkimage inputs"
cp "$UBOOT_DIR/spl/u-boot-spl.bin" "$MKIMAGE_DIR/iMX8M/u-boot-spl.bin"
cp "$UBOOT_DIR/u-boot-nodtb.bin" "$MKIMAGE_DIR/iMX8M/u-boot-nodtb.bin"
cp "$UBOOT_DIR/arch/arm/dts/$DTB" "$MKIMAGE_DIR/iMX8M/$DTB"
cp "$UBOOT_DIR/tools/mkimage" "$MKIMAGE_DIR/iMX8M/mkimage_uboot"
cp "$BL31" "$MKIMAGE_DIR/iMX8M/bl31.bin"
for firmware in "${!DDR_FW[@]}"; do
	cp "$DDR_FW_DIR/$firmware" "$MKIMAGE_DIR/iMX8M/${DDR_FW[$firmware]}"
done

# imx-mkimage generates u-boot.itb itself from u-boot-nodtb.bin + DTB + bl31.bin
echo "Packaging flash.bin"
# imx-mkimage derives paths from $PWD, so cd rather than make -C
cd "$MKIMAGE_DIR"
make -C iMX8M -f soc.mak clean
make SOC=iMX8MM dtbs="$DTB" flash_evk_no_hdmi

echo "Created: $MKIMAGE_DIR/iMX8M/flash.bin"