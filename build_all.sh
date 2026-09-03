#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LINEAGE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PUSH_BRANCH="lineage-22.2"

# vendor/<vendor>/<codename> relative to $LINEAGE_ROOT
# Corresponding build script: ./build_<codename>.sh
DEVICES=(
    bananapi/m5
    radxa/radxa0
    radxa/radxa02
    radxa/radxa02pro
    hardkernel/odroidc4
)

export BUILD_DIR="$SCRIPT_DIR"
export UBOOT_BIN="${BUILD_DIR}/uboot-bins/u-boot.bin"

for device in "${DEVICES[@]}"; do
    codename="${device##*/}"
    build="${BUILD_DIR}/build_${codename}.sh"
    export DEVICE_PATH="${LINEAGE_ROOT}/device/${device}"
    vendor_path="${LINEAGE_ROOT}/vendor/${device}"
    radio="${vendor_path}/radio"

    cd "$BUILD_DIR"
    mkdir -p "$radio"

    FORCE_RECOVERY=true  "$build"
    mv "$UBOOT_BIN" "${radio}/bootloader-recovery.img"

    CONSOLE_ENABLED=true "$build"
    mv "$UBOOT_BIN" "${radio}/bootloader-console.img"

    "$build"
    mv "$UBOOT_BIN" "${radio}/bootloader.img"

    # Regenerate vendor makefiles for the new prebuilts
    cd "$DEVICE_PATH"
    ./setup-makefiles.py

    cd "$vendor_path"
    git add -A
    git commit -m "${codename}: Update bootloader image prebuilts"
    #git push private "HEAD:refs/heads/${PUSH_BRANCH}"
done

cd "$BUILD_DIR"
