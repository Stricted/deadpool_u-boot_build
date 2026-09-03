#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

BOARD=sm1_odroidc4_v1
FIP_DIR=fip-collect-g12a-odroidc4-odroidg12-v2015.01-20210623-153349
UBOOT_BIN="${SCRIPT_DIR}/uboot-bins/u-boot.bin"
LINEAGE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VENDOR_PATH="${LINEAGE_ROOT}/vendor/hardkernel/odroidc4"
DEVICE_PATH="${LINEAGE_ROOT}/device/hardkernel/odroidc4"
RADIO="${VENDOR_PATH}/radio"

[[ -d "${VENDOR_PATH}" ]] && mkdir -p "$RADIO"

./build.sh "$BOARD" board/amlogic/defconfigs/fragments/recovery.cfg
./generate-bins-new.sh "$FIP_DIR" ../u-boot/build/u-boot.bin "${BOARD}-recovery"
[[ -d "${VENDOR_PATH}" ]] && cp "$UBOOT_BIN" "${RADIO}/bootloader-recovery.img"

./build.sh "$BOARD" board/amlogic/defconfigs/fragments/console.cfg
./generate-bins-new.sh "$FIP_DIR" ../u-boot/build/u-boot.bin "${BOARD}-console"
[[ -d "${VENDOR_PATH}" ]] && cp "$UBOOT_BIN" "${RADIO}/bootloader-console.img"

./build.sh "$BOARD"
./generate-bins-new.sh "$FIP_DIR" ../u-boot/build/u-boot.bin "${BOARD}-base"
[[ -d "${VENDOR_PATH}" ]] && cp "$UBOOT_BIN" "${RADIO}/bootloader.img"

if [[ -d "${DEVICE_PATH}" ]]; then
    cd "$DEVICE_PATH" && ./setup-makefiles.py
fi
if [[ -d "${VENDOR_PATH}" ]]; then
    cd "$VENDOR_PATH" && git add -A && git commit -m "odroidc4: Update bootloader image prebuilts"
fi
