#!/usr/bin/env bash
set -Eeuo pipefail

KERNEL_DIR="${KERNEL_DIR:-$HOME/linux-imx}"
UBOOT_DIR="${UBOOT_DIR:-$HOME/uboot-imx}"
REPO_DIR="${REPO_DIR:-/mnt/c/My Drive/Ender Folder/Projects/crls design/M8 Minima}"
FRAGMENT="${FRAGMENT:-$REPO_DIR/bsp/kernel/m8-minima.config}"
OUT_DIR="${OUT_DIR:-$HOME/m8-minima-kernel}"

# Board DTS is shared with U-Boot; this is the single copy that gets edited
BOARD_DTS="${BOARD_DTS:-$UBOOT_DIR/dts/upstream/src/arm64/freescale/imx8mm-m8-minima.dts}"
DTB_NAME=imx8mm-m8-minima.dtb

CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
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

need_dir "$KERNEL_DIR"
need_file "$BOARD_DTS"
need_file "$FRAGMENT"

kmake() {
	make -C "$KERNEL_DIR" -j"$JOBS" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" "$@"
}

echo "Installing board device tree"
DTS_DIR="$KERNEL_DIR/arch/arm64/boot/dts/freescale"
# NXP's linux-imx imx8mm-evk.dtsi carries extra EVK hardware (display,
# AK4458/AK5558 audio on SAI1/SAI5, ...). Build against the same mainline
# EVK base U-Boot uses so both see an identical board DT.
EVK_BASE="$(dirname "$BOARD_DTS")/imx8mm-evk.dtsi"
need_file "$EVK_BASE"
cp "$EVK_BASE" "$DTS_DIR/imx8mm-m8-minima-evk-base.dtsi"
sed 's/#include "imx8mm-evk.dtsi"/#include "imx8mm-m8-minima-evk-base.dtsi"/' \
	"$BOARD_DTS" > "$DTS_DIR/imx8mm-m8-minima.dts"
grep -q 'imx8mm-m8-minima-evk-base.dtsi' "$DTS_DIR/imx8mm-m8-minima.dts" ||
	die "board DTS does not include imx8mm-evk.dtsi as expected"
grep -q "$DTB_NAME" "$DTS_DIR/Makefile" ||
	sed -i "0,/imx8mm-evk.dtb/s//imx8mm-evk.dtb $DTB_NAME/" "$DTS_DIR/Makefile"
grep -q "$DTB_NAME" "$DTS_DIR/Makefile" || die "could not add $DTB_NAME to $DTS_DIR/Makefile"

echo "Configuring kernel (imx_v8_defconfig + $(basename "$FRAGMENT"))"
kmake imx_v8_defconfig
tr -d '\r' < "$FRAGMENT" > "$KERNEL_DIR/.m8-minima.config"
(cd "$KERNEL_DIR" &&
	ARCH=arm64 scripts/kconfig/merge_config.sh -m .config .m8-minima.config >/dev/null)
kmake olddefconfig

# merge_config only warns; fail if a requested option didn't stick
missing=0
while IFS= read -r line; do
	[[ "$line" =~ ^CONFIG_[A-Z0-9_]+=[ym]$ ]] || continue
	opt="${line%%=*}"
	grep -Eq "^${opt}=(y|m)$" "$KERNEL_DIR/.config" || {
		echo "warning: $opt not set in final .config" >&2
		missing=1
	}
done < "$KERNEL_DIR/.m8-minima.config"
[[ $missing -eq 0 ]] || die "config fragment did not fully apply"

echo "Building Image, modules, and $DTB_NAME"
kmake Image modules "freescale/$DTB_NAME"

echo "Staging output in $OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/boot"
cp "$KERNEL_DIR/arch/arm64/boot/Image" "$OUT_DIR/boot/"
cp "$DTS_DIR/$DTB_NAME" "$OUT_DIR/boot/"
kmake modules_install INSTALL_MOD_PATH="$OUT_DIR" INSTALL_MOD_STRIP=1 >/dev/null

echo "Created: $OUT_DIR/boot/Image"
echo "Created: $OUT_DIR/boot/$DTB_NAME"
echo "Created: $OUT_DIR/lib/modules/$(make -s -C "$KERNEL_DIR" kernelrelease)"
