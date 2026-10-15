#!/usr/bin/env bash
# Build a bootable M8 Minima SD card image: flash.bin + Debian arm64 rootfs.
#
# Run as root inside WSL (debootstrap needs chroot/mknod/chown):
#   sudo bash build-sdcard-m8-minima.sh
#
# One-time host setup (Ubuntu 20.04): focal's debootstrap (1.0.118) and qemu
# (4.2) are too old for trixie, so current Debian builds are unpacked, not
# installed, under ~/tools:
#   sudo apt install gnupg wget
#   wget https://deb.debian.org/debian/pool/main/d/debootstrap/debootstrap_1.0.145_all.deb
#   dpkg-deb -x debootstrap_1.0.145_all.deb ~/tools/debootstrap
#   wget https://deb.debian.org/debian/pool/main/q/qemu/qemu-user_10.0.13+ds-0+deb13u1_amd64.deb
#   dpkg-deb -x qemu-user_10.0.13+ds-0+deb13u1_amd64.deb ~/tools/qemu
set -Eeuo pipefail

BUILD_USER="${SUDO_USER:-$(id -un)}"
BUILD_HOME="$(getent passwd "$BUILD_USER" | cut -d: -f6)"

DEBOOTSTRAP="${DEBOOTSTRAP:-$BUILD_HOME/tools/debootstrap/usr/sbin/debootstrap}"
export DEBOOTSTRAP_DIR="${DEBOOTSTRAP_DIR:-$BUILD_HOME/tools/debootstrap/usr/share/debootstrap}"
# Static-PIE; qemu 4.2 lacks F_OFD_SETLK, which breaks systemd-sysusers
QEMU="${QEMU:-$BUILD_HOME/tools/qemu/usr/bin/qemu-aarch64}"

SUITE="${SUITE:-trixie}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
WORK_DIR="${WORK_DIR:-$BUILD_HOME/m8-minima-rootfs}"
KERNEL_OUT="${KERNEL_OUT:-$BUILD_HOME/m8-minima-kernel}"
FLASH_BIN="${FLASH_BIN:-$BUILD_HOME/imx-mkimage/iMX8M/flash.bin}"
IMG="${IMG:-$BUILD_HOME/m8-minima-sdcard.img}"
IMG_SIZE_MIB="${IMG_SIZE_MIB:-3072}"	# grown to fill the card on first boot

HOSTNAME_M8="${HOSTNAME_M8:-m8-minima}"
USER_NAME="${USER_NAME:-m8}"
USER_PASS="${USER_PASS:-m8minima}"	# expired: must be changed at first login

# i.MX8MM boot ROM reads the boot image at 33 KiB on SD; rootfs starts at 16 MiB
FLASH_BIN_OFFSET_KIB=33
PART_START_SECTOR=32768
DISK_ID=0x4d384d31			# fixed MBR id -> root=PARTUUID=4d384d31-01
ROOT_PARTUUID=4d384d31-01

# debootstrap doesn't resolve virtual packages: dbus is listed explicitly
# because network-manager/bluez only depend on default-dbus-system-bus
PACKAGES=(
	dbus ca-certificates sudo openssh-server locales
	systemd-timesyncd iproute2 iputils-ping kmod
	cloud-guest-utils e2fsprogs
	firmware-iwlwifi wireless-regdb network-manager wpasupplicant iw rfkill hostapd bluez
	nano less
)

die() {
	echo "error: $*" >&2
	exit 1
}

need_file() {
	[[ -f "$1" ]] || die "missing file: $1"
}

need_command() {
	command -v "$1" >/dev/null 2>&1 || die "missing command: $1 (see one-time host setup)"
}

[[ $EUID -eq 0 ]] || die "run as root: sudo bash $0"
for c in gpg wget sfdisk mke2fs depmod; do
	need_command "$c"
done
need_file "$DEBOOTSTRAP"
need_file "$QEMU"
need_file "$DEBOOTSTRAP_DIR/scripts/$SUITE"
need_file "$FLASH_BIN"
need_file "$KERNEL_OUT/boot/Image"
need_file "$KERNEL_OUT/boot/imx8mm-m8-minima.dtb"
KVER="$(ls "$KERNEL_OUT/lib/modules")"
[[ -n "$KVER" && -d "$KERNEL_OUT/lib/modules/$KVER" ]] || die "no modules in $KERNEL_OUT/lib/modules"

echo "Registering arm64 emulation ($("$QEMU" --version | head -1))"
BINFMT=/proc/sys/fs/binfmt_misc
mountpoint -q "$BINFMT" || mount -t binfmt_misc binfmt_misc "$BINFMT"
# Shadow any host qemu-aarch64 entry for the build, restore it on exit.
# F = open the interpreter now, so the chroot doesn't need its own copy.
HOST_ENTRY_WAS_ENABLED=0
if [[ -e "$BINFMT/qemu-aarch64" ]] && grep -q '^enabled' "$BINFMT/qemu-aarch64"; then
	HOST_ENTRY_WAS_ENABLED=1
	echo 0 > "$BINFMT/qemu-aarch64"
fi
restore_binfmt() {
	[[ -e "$BINFMT/qemu-aarch64-m8" ]] && echo -1 > "$BINFMT/qemu-aarch64-m8"
	[[ $HOST_ENTRY_WAS_ENABLED -eq 1 ]] && echo 1 > "$BINFMT/qemu-aarch64"
	return 0
}
trap restore_binfmt EXIT
[[ -e "$BINFMT/qemu-aarch64-m8" ]] && echo -1 > "$BINFMT/qemu-aarch64-m8"
echo ':qemu-aarch64-m8:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:'"$QEMU"':FOC' \
	> "$BINFMT/register"
grep -q '^enabled' "$BINFMT/qemu-aarch64-m8" || die "failed to register $QEMU with binfmt_misc"

ROOT="$WORK_DIR/root"
rm -rf "$WORK_DIR"
mkdir -p "$ROOT"

echo "Fetching Debian archive signing keys"
KEYRING="$WORK_DIR/debian-archive.gpg"
for n in 12 13; do
	wget -q -O "$WORK_DIR/archive-key-$n.asc" "https://ftp-master.debian.org/keys/archive-key-$n.asc"
done
cat "$WORK_DIR"/archive-key-*.asc | gpg --dearmor > "$KEYRING"

echo "debootstrap $SUITE arm64, first stage"
"$DEBOOTSTRAP" --arch=arm64 --foreign --keyring="$KEYRING" \
	--components=main,non-free-firmware \
	--include="$(IFS=,; echo "${PACKAGES[*]}")" \
	"$SUITE" "$ROOT" "$MIRROR"

echo "debootstrap second stage (takes a while under qemu)"
# Inside the chroot debootstrap must use its own copy, not the host's DEBOOTSTRAP_DIR
DEBOOTSTRAP_DIR=/debootstrap chroot "$ROOT" /debootstrap/debootstrap --second-stage

echo "Configuring rootfs"
cat > "$ROOT/etc/apt/sources.list.d/debian.sources" <<EOF
Types: deb
URIs: $MIRROR
Suites: $SUITE $SUITE-updates
Components: main non-free-firmware

Types: deb
URIs: http://security.debian.org/debian-security
Suites: $SUITE-security
Components: main non-free-firmware
EOF
rm -f "$ROOT/etc/apt/sources.list"

echo "$HOSTNAME_M8" > "$ROOT/etc/hostname"
cat > "$ROOT/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	$HOSTNAME_M8
::1		localhost ip6-localhost ip6-loopback
EOF

cat > "$ROOT/etc/fstab" <<EOF
PARTUUID=$ROOT_PARTUUID	/	ext4	defaults,noatime	0	1
EOF

sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' "$ROOT/etc/locale.gen"
chroot "$ROOT" locale-gen >/dev/null
echo 'LANG=en_US.UTF-8' > "$ROOT/etc/default/locale"

chroot "$ROOT" useradd -m -s /bin/bash -G sudo "$USER_NAME"
echo "$USER_NAME:$USER_PASS" | chroot "$ROOT" chpasswd
chroot "$ROOT" chage -d 0 "$USER_NAME"
chroot "$ROOT" passwd -l root >/dev/null

# Grow the root partition + filesystem to the full card on first boot
cat > "$ROOT/usr/local/sbin/m8-growroot" <<'EOF'
#!/bin/sh
set -e
src=$(findmnt -no SOURCE /)
disk=/dev/$(lsblk -no PKNAME "$src")
part=$(cat /sys/class/block/$(basename "$src")/partition)
growpart "$disk" "$part" || true
resize2fs "$src"
systemctl disable m8-growroot.service
EOF
chmod 755 "$ROOT/usr/local/sbin/m8-growroot"
cat > "$ROOT/etc/systemd/system/m8-growroot.service" <<'EOF'
[Unit]
Description=Grow root filesystem to fill the SD card
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/m8-growroot

[Install]
WantedBy=multi-user.target
EOF
chroot "$ROOT" systemctl enable m8-growroot.service >/dev/null 2>&1
# Debug console on UART2 (ttymxc1) comes from console=; add UART4 (ttymxc3)
chroot "$ROOT" systemctl enable serial-getty@ttymxc3.service >/dev/null 2>&1

echo "Installing kernel $KVER"
mkdir -p "$ROOT/boot/extlinux" "$ROOT/usr/lib/modules"
cp "$KERNEL_OUT/boot/Image" "$KERNEL_OUT/boot/imx8mm-m8-minima.dtb" "$ROOT/boot/"
cp -a "$KERNEL_OUT/lib/modules/$KVER" "$ROOT/usr/lib/modules/"
depmod -b "$ROOT" "$KVER"
cat > "$ROOT/boot/extlinux/extlinux.conf" <<EOF
default m8-minima
timeout 3

label m8-minima
	kernel /boot/Image
	fdt /boot/imx8mm-m8-minima.dtb
	append root=PARTUUID=$ROOT_PARTUUID rootwait rw console=ttymxc1,115200
EOF

chroot "$ROOT" apt-get clean
rm -f "$ROOT"/var/lib/apt/lists/*_Packages "$ROOT"/var/lib/apt/lists/*_Release*

echo "Building $IMG (${IMG_SIZE_MIB} MiB)"
ROOT_IMG="$WORK_DIR/root.ext4"
ROOT_MIB=$((IMG_SIZE_MIB - PART_START_SECTOR / 2048))
rm -f "$ROOT_IMG" "$IMG"
mke2fs -q -t ext4 -L m8-root -d "$ROOT" "$ROOT_IMG" "${ROOT_MIB}M"
truncate -s "${IMG_SIZE_MIB}M" "$IMG"
sfdisk -q "$IMG" <<EOF
label: dos
label-id: $DISK_ID
start=$PART_START_SECTOR, type=83, bootable
EOF
dd if="$ROOT_IMG" of="$IMG" bs=1M seek=$((PART_START_SECTOR / 2048)) conv=notrunc,fsync status=none
dd if="$FLASH_BIN" of="$IMG" bs=1K seek=$FLASH_BIN_OFFSET_KIB conv=notrunc,fsync status=none
chown "$BUILD_USER:" "$IMG"
rm -f "$ROOT_IMG"

echo "Created: $IMG"
echo "Login: $USER_NAME / $USER_PASS (must be changed at first login)"
