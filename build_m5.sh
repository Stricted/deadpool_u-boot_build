#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

SOC=sm1
BOARD=sm1_bananapim5_v1
UBOOT_BIN="${SCRIPT_DIR}/uboot-bins/u-boot.bin"
LINEAGE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
VENDOR_PATH="${LINEAGE_ROOT}/vendor/bananapi/m5"
DEVICE_PATH="${LINEAGE_ROOT}/device/bananapi/m5"
RADIO="${VENDOR_PATH}/radio"

[[ -d "${VENDOR_PATH}" ]] && mkdir -p "$RADIO"

./collect-m5_binaries-git-refboard.sh "$SOC" "$BOARD" board/amlogic/defconfigs/fragments/recovery.cfg
[[ -d "${VENDOR_PATH}" ]] && cp "$UBOOT_BIN" "${RADIO}/bootloader-recovery.img"

./collect-m5_binaries-git-refboard.sh "$SOC" "$BOARD" board/amlogic/defconfigs/fragments/console.cfg
[[ -d "${VENDOR_PATH}" ]] && cp "$UBOOT_BIN" "${RADIO}/bootloader-console.img"

./collect-m5_binaries-git-refboard.sh "$SOC" "$BOARD"
[[ -d "${VENDOR_PATH}" ]] && cp "$UBOOT_BIN" "${RADIO}/bootloader.img"

if [[ -d "${DEVICE_PATH}" ]]; then
    cd "$DEVICE_PATH" && ./setup-makefiles.py
fi
if [[ -d "${VENDOR_PATH}" ]]; then
    cd "$VENDOR_PATH" && git add -A && git commit -m "m5: Update bootloader image prebuilts"
fi
