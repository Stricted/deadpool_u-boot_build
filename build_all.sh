#!/bin/bash
set -euo pipefail

LINEAGE_ROOT="${HOME}/lineage-22"
BRANCH="lineage-22.2"

# Vendor/codename, relative to $LINEAGE_ROOT.
# Build script is assumed to be ./build_<codename>.sh
DEVICES=(
	bananapi/m5
	radxa/radxa0
	radxa/radxa02
	radxa/radxa02pro
	hardkernel/odroidc4
)

export BUILD_DIR="$(pwd)"
export UBOOT_BIN="${BUILD_DIR}/uboot-bins/u-boot.bin"

for device in "${DEVICES[@]}"; do
	codename="${device##*/}"
	build="./build_${codename}.sh"
	export DEVICE_PATH="${LINEAGE_ROOT}/device/${device}"
	vendor_path="${LINEAGE_ROOT}/vendor/${device}"
	radio="${vendor_path}/radio"

	cd "$BUILD_DIR"
	mkdir -p "$radio"

	FORCE_RECOVERY=true "$build"
	mv "$UBOOT_BIN" "${radio}/bootloader-recovery.img"

	CONSOLE_ENABLED=true "$build"
	mv "$UBOOT_BIN" "${radio}/bootloader-console.img"

	"$build"
	mv "$UBOOT_BIN" "${radio}/bootloader.img"

	# Regenerate the vendor makefiles for the new prebuilts
	cd "$DEVICE_PATH"
	./setup-makefiles.py

	cd "$vendor_path"
	git add -A
	git commit -m "${codename}: Update bootloader image prebuilts"
	#git push private "HEAD:refs/heads/${BRANCH}"
done

cd "$BUILD_DIR"
