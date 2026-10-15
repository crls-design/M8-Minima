#!/usr/bin/env bash
# Fetch sources, apply the bsp/modules overlays, then build the bootloader
# (TF-A + U-Boot -> flash.bin) and the kernel. Run inside WSL:
#
#   REPO="/mnt/c/My Drive/Ender Folder/Projects/crls design/M8 Minima"
#   tr -d '\r' < "$REPO/scripts/build-m8-minima.sh" | bash -s -- [all|bootloader|kernel]
#
# The SD card image needs root and is a separate step:
#   tr -d '\r' < "$REPO/scripts/build-sdcard-m8-minima.sh" | sudo bash
set -Eeuo pipefail

export REPO_DIR="${REPO_DIR:-/mnt/c/My Drive/Ender Folder/Projects/crls design/M8 Minima}"
export UBOOT_DIR="${UBOOT_DIR:-$HOME/uboot-imx}"
export ATF_DIR="${ATF_DIR:-$HOME/arm-trusted-firmware}"
export KERNEL_DIR="${KERNEL_DIR:-$HOME/linux-imx}"
export MKIMAGE_DIR="${MKIMAGE_DIR:-$HOME/imx-mkimage}"

export CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
export CC="${CC:-aarch64-linux-gnu-gcc-10}"
export JOBS="${JOBS:-$(nproc)}"

TARGET="${1:-all}"

die() {
	echo "error: $*" >&2
	exit 1
}

# Repo scripts live on the Windows side; strip CR in case they picked any up
run_script() {
	local script="$REPO_DIR/scripts/$1"
	[[ -f "$script" ]] || die "missing file: $script"
	tr -d '\r' < "$script" | bash
}

build_bootloader() {
	echo "Building TF-A BL31"
	make -C "$ATF_DIR" -j"$JOBS" PLAT=imx8mm CROSS_COMPILE="$CROSS_COMPILE" bl31

	echo "Configuring U-Boot (m8_minima_defconfig)"
	make -C "$UBOOT_DIR" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" CC="$CC" m8_minima_defconfig

	run_script package-m8-minima.sh
	cp "$MKIMAGE_DIR/iMX8M/flash.bin" "$REPO_DIR/bsp/flash.bin"
	echo "Copied flash.bin to $REPO_DIR/bsp/flash.bin"
}

case "$TARGET" in
	all | bootloader | kernel) ;;
	*) die "unknown target '$TARGET' (expected all, bootloader or kernel)" ;;
esac

run_script fetch-sources-m8-minima.sh

[[ "$TARGET" == kernel ]] || build_bootloader
[[ "$TARGET" == bootloader ]] || run_script build-kernel-m8-minima.sh

echo "Done ($TARGET)"
