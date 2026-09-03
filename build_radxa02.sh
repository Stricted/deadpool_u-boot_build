#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

export SOURCE_DATE_EPOCH=$(git -C "../u-boot" log -1 --pretty=%ct HEAD)

BOARD=sm1_radxa02_v1
FIP_DIR=fip-radxa02-220427
UBOOT_BIN="${SCRIPT_DIR}/uboot-bins/u-boot.bin"
LINEAGE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VENDOR_PATH="${LINEAGE_ROOT}/vendor/radxa/radxa02"
DEVICE_PATH="${LINEAGE_ROOT}/device/radxa/radxa02"
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
    cd "$VENDOR_PATH" && git add -A && git commit -m "radxa02: Update bootloader image prebuilts"
fi
