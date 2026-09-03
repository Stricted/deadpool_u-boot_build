#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

function usage() {
    echo "Usage: $0 [soc] [board] [fragment.cfg] [power-up key]"
}

if [[ $# -lt 2 ]]; then
    usage
    exit 22
fi

SOCFAMILY=${1}
REFBOARD=${2}
FRAGMENT=${3:-}
PWRKEYCODE=${4:-}

UBOOT_SRC="$(realpath "$(dirname "$0")/../u-boot")"

if ! [[ "$SOCFAMILY" == "g12a" || "$SOCFAMILY" == "g12b" || "$SOCFAMILY" == "sm1" ]]; then
    echo "${SOCFAMILY} is not supported - should be [g12a, g12b, sm1]"
    usage
    exit 22
fi

if [[ "$SOCFAMILY" == "sm1" ]]; then
    SOCFAMILY="g12a"
fi

bl2="bootloader/uboot-repo/bl2"
bl30="bootloader/uboot-repo/bl30"
bl31="bootloader/uboot-repo/bl31_1.3"
fip="bootloader/uboot-repo/fip"
dir="bootloader/uboot-repo"
TMP="uboot-bins-$(date +%Y%m%d-%H%M%S)"

TMP_GIT=$(mktemp -d)

TOOLCHAIN_PATH=

if command -v aarch64-none-elf-gcc &>/dev/null && command -v arm-none-eabi-gcc &>/dev/null; then
    echo "Using system toolchain"
else
    TOOLCHAIN_AARCH64=$TMP_GIT/gcc-linaro-aarch64-none-elf
    TOOLCHAIN_ARM=$TMP_GIT/gcc-linaro-arm-none-eabi

    mkdir "$TOOLCHAIN_AARCH64"
    wget -qO- https://mirror.twds.com.tw/armbian-dl/_toolchain/gcc-linaro-aarch64-none-elf-4.8-2013.11_linux.tar.xz \
        | tar -xJ --strip-components=1 -C "$TOOLCHAIN_AARCH64"

    mkdir "$TOOLCHAIN_ARM"
    wget -qO- https://mirror.twds.com.tw/armbian-dl/_toolchain/gcc-linaro-arm-none-eabi-4.8-2014.04_linux.tar.xz \
        | tar -xJ --strip-components=1 -C "$TOOLCHAIN_ARM"

    TOOLCHAIN_PATH="$TOOLCHAIN_AARCH64/bin:$TOOLCHAIN_ARM/bin:"
fi

# FIP blobs
get_src() {
    local branch="master"
    git clone -n --depth=1 --filter=tree:0 https://github.com/BPI-SINOVOIP/BPI-S905X3-Android9.git -b "$branch" "$TMP_GIT/FIP"
    (
        cd "$TMP_GIT/FIP"
        if [[ "$SOCFAMILY" == "g12b" ]]; then
            git sparse-checkout set --no-cone /$bl2 /$bl30 /$bl31 /$fip
        else
            git sparse-checkout set --no-cone /$bl2 /$bl31 /$fip
        fi
        git checkout
    )
}

get_src || exit

# Use pinned BPI-S905X3 commit for bl30 — newer blob causes "Undefined instructions" crash
if ! [[ "$SOCFAMILY" == "g12b" ]]; then
    get_bl30() {
        local branch="master"
        local commit="a538717a004e5a99927a755db5f5643c31caf6ce"
        git clone -n --depth=1 --filter=tree:0 https://github.com/BPI-SINOVOIP/BPI-S905X3-Android9.git -b "$branch" "$TMP_GIT/BL30"
        (
            cd "$TMP_GIT/BL30"
            git sparse-checkout set --no-cone /$bl30
            git config --global advice.detachedHead false && git checkout "$commit"
        )
    }
    get_bl30 || exit
fi

# U-Boot (bl33) — symlink into TMP_GIT so mk_script finds it at the expected path
ln -s "$UBOOT_SRC" "$TMP_GIT/bl33"

# Strip hardcoded toolchain paths — mk_script drives make internally so we
# can't override CROSS_COMPILE on the command line the way build.sh can
sed -i "s,/opt/gcc-.*/bin/,," "$TMP_GIT/bl33/Makefile"

cat > "$TMP_GIT/mk" << 'EOF'
#!/bin/bash
source fip/mk_script.sh
EOF
chmod a+rwx,o-w "$TMP_GIT/mk"

cp -r "$TMP_GIT/FIP/$dir"/* "$TMP_GIT/" && sync

if ! [[ "$SOCFAMILY" == "g12b" ]]; then
    cp -r "$TMP_GIT/BL30/$dir"/* "$TMP_GIT/" && sync
    sed -i "s/40960/47104/" "$TMP_GIT/fip/$SOCFAMILY/build.sh"
fi

# custom power-up key
if [[ -n "$PWRKEYCODE" ]]; then
    board_cfg="$TMP_GIT/bl33/board/amlogic/configs/${REFBOARD}.h"
    head_tmp="$(mktemp "$TMP_GIT/tmp.XXXX")"
    awk -v pwr_key="$PWRKEYCODE" \
        '{if ($2=="CONFIG_IR_REMOTE_POWER_UP_KEY_VAL6") $3=pwr_key; print $0}' \
        "$board_cfg" > "$head_tmp"
    cp "$head_tmp" "$board_cfg"
fi

sed -i "190d" "$TMP_GIT/fip/lib.sh"
sed -i "s/ \x24\x7BBL33_DEFCFG2\x7D\x2F\*//" "$TMP_GIT/fip/build_bl33.sh"

# Pre-configure u-boot so mk uses our .config rather than running defconfig itself
(
    cd "$TMP_GIT/bl33"
    rm -rf build/
    PATH="${TOOLCHAIN_PATH}${PATH}" CROSS_COMPILE=aarch64-none-elf- make "${REFBOARD}_defconfig"
    if [[ -n "${FRAGMENT}" ]]; then
        ./scripts/kconfig/merge_config.sh -O build build/.config "${FRAGMENT}"
    fi
)
# Replace the defconfig step in build_bl33.sh with a no-op
sed -i 's/make .*_defconfig.*/true/' "$TMP_GIT/fip/build_bl33.sh"

SOURCE_DATE_EPOCH=$(git -C "$UBOOT_SRC" log -1 --pretty=%ct HEAD)
export SOURCE_DATE_EPOCH

(
    cd "$TMP_GIT"
    PATH="${TOOLCHAIN_PATH}${PATH}" CROSS_COMPILE=aarch64-none-elf- ./mk "${REFBOARD}" > /dev/null
)

mkdir "$TMP"
ln -sfn "$TMP" uboot-bins

cp "$TMP_GIT/build"/{u-boot.bin,u-boot.bin.sd.bin,u-boot.bin.usb.bl2,u-boot.bin.usb.tpl} "$TMP/" && sync
dd if="$TMP/u-boot.bin" of="$TMP/sd.img" conv=fsync bs=512 seek=1

date > "$TMP/info.txt"
echo "COMMIT: $(git -C "$UBOOT_SRC" rev-parse HEAD)" >> "$TMP/info.txt"

if [[ "$SOCFAMILY" == "g12b" ]]; then
    dd if="$TMP_GIT/bl30/bin/$SOCFAMILY/bl30.bin" of="$TMP_GIT/bl30_info.bin" bs=$((0x1)) count=$((0x44)) skip=$((0x7420))
else
    dd if="$TMP_GIT/bl30/bin/$SOCFAMILY/bl30.bin" of="$TMP_GIT/bl30_info.bin" bs=$((0x1)) count=$((0x44)) skip=$((0x77b4))
fi
echo "bl30: $(< "$TMP_GIT/bl30_info.bin")" >> "$TMP/info.txt"

for component in "$TMP_GIT"/*; do
    if [[ -d "$component/.git" ]]; then
        echo "$(basename "$component"): $(git --git-dir="$component/.git" log --pretty=format:%H -1 HEAD)" >> "$TMP/info.txt"
    fi
done

if [[ "$REFBOARD" == "sm1_bananapim5_v1" ]]; then
    dd if="$TMP_GIT/fip/$SOCFAMILY/aml_ddr.fw" of="$TMP_GIT/fw_version.bin" bs=$((0x1)) count=$((0x13)) skip=$((0xb225))
    dd if="$TMP_GIT/fip/$SOCFAMILY/aml_ddr.fw" of="$TMP_GIT/fw_built.bin"   bs=$((0x1)) count=$((0x46)) skip=$((0xad78))
    sed -i "s/ :/:/" "$TMP_GIT/fw_built.bin" | echo "DDR-FIRMWARE: $(< "$TMP_GIT/fw_version.bin")" >> "$TMP/info.txt"
    echo "$(< "$TMP_GIT/fw_built.bin")" >> "$TMP/info.txt"
    SOCFAMILY="sm1"
fi

[[ -n "$PWRKEYCODE" ]] && echo "KEY-POWER: $PWRKEYCODE" >> "$TMP/info.txt"
[[ -n "$FRAGMENT"   ]] && echo "FRAGMENT: $FRAGMENT"    >> "$TMP/info.txt"

echo "SOC: $SOCFAMILY"   >> "$TMP/info.txt"
echo "BOARD: $REFBOARD"  >> "$TMP/info.txt"

rm -rf "${TMP_GIT}"
