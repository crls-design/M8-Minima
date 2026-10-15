#!/usr/bin/env bash
# Clone the upstream repos at their pinned base commits and copy the
# bsp/modules/<repo>/ overlays over them.
#
# Safe to re-run: an existing clone is reused (the base commit is fetched only
# if missing) and the overlay is copied again on top. Files the overlay would
# overwrite with different content are backed up to $BACKUP_DIR first, so
# edits made directly in a WSL clone aren't lost silently.
#
# If a clone is not at its base commit (the pin changed) and has local
# changes, the script stops; re-run with FORCE=1 to discard them.
#
# The pins mirror bsp/modules/README.md; update both together.
set -Eeuo pipefail

REPO_DIR="${REPO_DIR:-/mnt/c/My Drive/Ender Folder/Projects/crls design/M8 Minima}"
OVERLAY_DIR="$REPO_DIR/bsp/modules"

UBOOT_DIR="${UBOOT_DIR:-$HOME/uboot-imx}"
ATF_DIR="${ATF_DIR:-$HOME/arm-trusted-firmware}"
KERNEL_DIR="${KERNEL_DIR:-$HOME/linux-imx}"
MKIMAGE_DIR="${MKIMAGE_DIR:-$HOME/imx-mkimage}"

BACKUP_DIR="${BACKUP_DIR:-$HOME/m8-minima-overlay-backup/$(date +%Y%m%d-%H%M%S)}"
FORCE="${FORCE:-0}"

# overlay folder | clone dir | url | branch | base commit
SOURCES=(
	"uboot-imx|$UBOOT_DIR|https://github.com/nxp-imx/uboot-imx.git|lf_v2026.04|bb41975aeb4cbd153b49c9fd62da1d64cd65968d"
	"arm-trusted-firmware|$ATF_DIR|https://github.com/ARM-software/arm-trusted-firmware.git|master|d2a8287d34fa4571e6e68204f903ac8c2a43ed5d"
	"linux-imx|$KERNEL_DIR|https://github.com/nxp-imx/linux-imx.git|lf-6.18.y|6e694eda40aabd6671fca82b5416dbd76beeebb9"
	"imx-mkimage|$MKIMAGE_DIR|https://github.com/nxp-imx/imx-mkimage.git|lf-6.18.20_2.0.0|1b577853ae1afe1f26cdef27548da52fb424af48"
)

# Local branch the base commit is checked out on
WORK_BRANCH=m8-minima

die() {
	echo "error: $*" >&2
	exit 1
}

need_dir() {
	[[ -d "$1" ]] || die "missing directory: $1"
}

need_command() {
	command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

need_command git
need_dir "$OVERLAY_DIR"

checkout_base() {
	local dir="$1" url="$2" branch="$3" commit="$4"

	if [[ ! -d "$dir/.git" ]]; then
		[[ ! -e "$dir" || -z "$(ls -A "$dir")" ]] ||
			die "$dir exists but is not a git repo"
		echo "Cloning $url ($branch @ ${commit:0:12})"
		git init -q "$dir"
		git -C "$dir" remote add origin "$url"
		# Shallow fetch of just the base commit; 'git fetch --unshallow' for history
		git -C "$dir" fetch -q --depth 1 origin "$commit"
		git -C "$dir" checkout -q -b "$WORK_BRANCH" "$commit"
		return
	fi

	local origin
	origin="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
	[[ "${origin%.git}" == "${url%.git}" ]] ||
		die "$dir: origin is '$origin', expected $url"

	if [[ "$(git -C "$dir" rev-parse HEAD)" == "$commit" ]]; then
		echo "$dir is at base commit ${commit:0:12}"
		return
	fi

	echo "$dir is not at base commit ${commit:0:12}; checking it out"
	git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null ||
		git -C "$dir" fetch -q --depth 1 origin "$commit"
	if [[ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]]; then
		[[ "$FORCE" == 1 ]] ||
			die "$dir has local changes; commit/export them or re-run with FORCE=1 to discard"
		git -C "$dir" checkout -q -f -B "$WORK_BRANCH" "$commit"
	else
		git -C "$dir" checkout -q -B "$WORK_BRANCH" "$commit"
	fi
}

apply_overlay() {
	local name="$1" dir="$2"
	local overlay="$OVERLAY_DIR/$name"
	local added=0 updated=0 unchanged=0
	local src rel dst tmp

	[[ -d "$overlay" ]] || return 0
	echo "Copying overlay bsp/modules/$name"
	tmp="$(mktemp)"
	while IFS= read -r -d '' src; do
		rel="${src#"$overlay/"}"
		dst="$dir/$rel"
		# Text files from the Windows side may have picked up CRLF
		if [[ ! -s "$src" ]] || grep -Iq . "$src"; then
			tr -d '\r' < "$src" > "$tmp"
		else
			cp "$src" "$tmp"
		fi
		if [[ -f "$dst" ]]; then
			if cmp -s "$tmp" "$dst"; then
				unchanged=$((unchanged + 1))
				continue
			fi
			# Pristine upstream files can be restored from git; back up the rest
			if ! git -C "$dir" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 ||
				! git -C "$dir" diff --quiet HEAD -- "$rel"; then
				install -D -m 0644 "$dst" "$BACKUP_DIR/$name/$rel"
			fi
			echo "  updated: $rel"
			updated=$((updated + 1))
		else
			echo "  added:   $rel"
			added=$((added + 1))
		fi
		install -D -m 0644 "$tmp" "$dst"
	done < <(find "$overlay" -type f -print0 | sort -z)
	rm -f "$tmp"
	echo "  $added added, $updated updated, $unchanged unchanged"
}

for entry in "${SOURCES[@]}"; do
	IFS='|' read -r name dir url branch commit <<< "$entry"
	checkout_base "$dir" "$url" "$branch" "$commit"
	apply_overlay "$name" "$dir"
done

if [[ -d "$BACKUP_DIR" ]]; then
	echo "Overwritten files backed up to $BACKUP_DIR"
fi
echo "Sources ready"
