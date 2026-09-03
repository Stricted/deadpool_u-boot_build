#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

function usage() {
    echo "Usage: $0 [board] [fragment.cfg]"
}

if [[ $# -lt 1 ]]; then
    usage
    exit 22
fi

REFBOARD=${1}
FRAGMENT=${2:-}

UBOOT_SRC="$(dirname "$0")/../u-boot"
TOOLCHAIN_PATH=

if command -v aarch64-none-elf-gcc &>/dev/null && command -v arm-none-eabi-gcc &>/dev/null; then
    echo "Using system toolchain"
else
    OUT=$(pwd)/out
    TOOLCHAIN_AARCH64=$OUT/gcc-linaro-aarch64-none-elf
    TOOLCHAIN_ARM=$OUT/gcc-linaro-arm-none-eabi

    if [[ ! -d "$TOOLCHAIN_AARCH64" ]]; then
        mkdir -p "$TOOLCHAIN_AARCH64"
        wget -qO- https://mirror.twds.com.tw/armbian-dl/_toolchain/gcc-linaro-aarch64-none-elf-4.8-2013.11_linux.tar.xz \
            | tar -xJ --strip-components=1 -C "$TOOLCHAIN_AARCH64"
    fi

    if [[ ! -d "$TOOLCHAIN_ARM" ]]; then
        mkdir -p "$TOOLCHAIN_ARM"
        wget -qO- https://mirror.twds.com.tw/armbian-dl/_toolchain/gcc-linaro-arm-none-eabi-4.8-2014.04_linux.tar.xz \
            | tar -xJ --strip-components=1 -C "$TOOLCHAIN_ARM"
    fi

    TOOLCHAIN_PATH="$TOOLCHAIN_AARCH64/bin:$TOOLCHAIN_ARM/bin:"
fi

SOURCE_DATE_EPOCH=$(git -C "$UBOOT_SRC" log -1 --pretty=%ct HEAD)
export SOURCE_DATE_EPOCH

(
    cd "$UBOOT_SRC"
    make "${REFBOARD}_defconfig"
    if [[ -n "${FRAGMENT}" ]]; then
        ./scripts/kconfig/merge_config.sh -O build build/.config "${FRAGMENT}"
    fi
    PATH="${TOOLCHAIN_PATH}${PATH}" CROSS_COMPILE=aarch64-none-elf- make -j$(nproc) > /dev/null
)
