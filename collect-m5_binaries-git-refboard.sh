#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset
set -o xtrace

<< "Description"
######################################################################
The goal of this script is gather all binaries provides by AML
in order to generate our final u-boot image from the u-boot.bin (bl33)

Some binaries come from the u-boot vendor
bl2.bin, bl30, bl31, aml_encrypt, ddr_parse, fip_create, ddr firmware
######################################################################
Description

function usage() {
    echo "Usage: $0 [u-boot branch] [soc] [refboard] [power-up key]"
}

if [[ $# -lt 3 ]]
then
    usage
    exit 22
elif [[ $# -eq 3 ]]
then
    PWRKEYCODE=
else
    PWRKEYCODE=${4}
fi

GITBRANCH=${1}
SOCFAMILY=${2}
REFBOARD=${3}

if ! [[ "$SOCFAMILY" == "g12a" || "$SOCFAMILY" == "g12b" || "$SOCFAMILY" == "sm1" ]]
then
    echo "${SOCFAMILY} is not supported - should be [g12a, g12b, sm1]"
    usage
    exit 22
fi

if [[ "$SOCFAMILY" == "sm1" ]]
then
    SOCFAMILY="g12a"
fi

bl2="bootloader/uboot-repo/bl2"
bl30="bootloader/uboot-repo/bl30"
bl31="bootloader/uboot-repo/bl31_1.3"
fip="bootloader/uboot-repo/fip"
dir="bootloader/uboot-repo"
TMP="uboot-bins-$(date +%Y%m%d-%H%M%S)"

# path to clone the u-boot repos
TMP_GIT=$(mktemp -d)

# FIP-binaries
get_src () {
    local GITBRANCH="master"
        git clone -n --depth=1 --filter=tree:0 https://github.com/BPI-SINOVOIP/BPI-S905X3-Android9.git -b $GITBRANCH $TMP_GIT/FIP
        (
            cd $TMP_GIT/FIP
            if [[ "$SOCFAMILY" == "g12b" ]]
            then
                git sparse-checkout set --no-cone /$bl2 /$bl30 /$bl31 /$fip
                git checkout
            else
                git sparse-checkout set --no-cone /$bl2 /$bl31 /$fip
                git checkout
            fi
        )
}

get_src "$@" || exit

# Use old BPI-S905X3 master branch to checkout bl30.bin, as the new blob leads to "Undefined instructions" crash
if ! [[ "$SOCFAMILY" == "g12b" ]]
then
    get_bl30 () {
        local GITBRANCH="master"
        commit="a538717a004e5a99927a755db5f5643c31caf6ce"
        git clone -n --depth=1 --filter=tree:0 https://github.com/BPI-SINOVOIP/BPI-S905X3-Android9.git -b $GITBRANCH $TMP_GIT/BL30
        (
            cd $TMP_GIT/BL30
            git sparse-checkout set --no-cone /$bl30
            git config --global advice.detachedHead false && git checkout $commit
        )
    }
    get_bl30 "$@" || exit
fi

# U-Boot
git clone --depth=2 https://github.com/Stricted/deadpool_u-boot.git -b $GITBRANCH $TMP_GIT/bl33
mkdir $TMP_GIT/gcc-linaro-aarch64-none-elf
wget -qO- https://releases.linaro.org/archive/13.11/components/toolchain/binaries/gcc-linaro-aarch64-none-elf-4.8-2013.11_linux.tar.xz | tar -xJ --strip-components=1 -C $TMP_GIT/gcc-linaro-aarch64-none-elf
mkdir $TMP_GIT/gcc-linaro-arm-none-eabi
wget -qO- https://releases.linaro.org/archive/13.11/components/toolchain/binaries/gcc-linaro-arm-none-eabi-4.8-2013.11_linux.tar.xz | tar -xJ --strip-components=1 -C $TMP_GIT/gcc-linaro-arm-none-eabi
sed -i "s,/opt/gcc-.*/bin/,," $TMP_GIT/bl33/Makefile

cat > $TMP_GIT/mk << EOF
#!/bin/bash
source fip/mk_script.sh
EOF
chmod a+rwx,o-w $TMP_GIT/mk

cp -r $TMP_GIT/FIP/$dir/* $TMP_GIT/ && sync

if ! [[ "$SOCFAMILY" == "g12b" ]]
then
    cp -r $TMP_GIT/BL30/$dir/* $TMP_GIT/ && sync
    sed -i "s/40960/47104/" $TMP_GIT/fip/$SOCFAMILY/build.sh
fi

# custom power-up key
if ! [[ -z "$PWRKEYCODE" ]]
then
    board_cfg="$TMP_GIT/bl33/board/amlogic/configs/${REFBOARD}.h"
    head_tmp="$(mktemp $TMP_GIT/tmp.XXXX)"
    awk -v pwr_key=${4} '{if ($2=="CONFIG_IR_REMOTE_POWER_UP_KEY_VAL6") $3=pwr_key; print $0}' $board_cfg > $head_tmp
    cp $head_tmp $board_cfg
fi

sed -i "190d" $TMP_GIT/fip/lib.sh
sed -i "s/ \x24\x7BBL33_DEFCFG2\x7D\x2F\*//" $TMP_GIT/fip/build_bl33.sh
(
    cd $TMP_GIT
    PATH=$TMP_GIT/gcc-linaro-aarch64-none-elf/bin:$TMP_GIT/gcc-linaro-arm-none-eabi/bin:$PATH CROSS_COMPILE=aarch64-none-elf- ./mk ${REFBOARD} > /dev/null
)

mkdir $TMP
ln -sfn $TMP uboot-bins

cp $TMP_GIT/build/{u-boot.bin,u-boot.bin.sd.bin,u-boot.bin.usb.bl2,u-boot.bin.usb.tpl} $TMP/ && sync
dd if=$TMP/u-boot.bin of=$TMP/sd.img conv=fsync bs=512 seek=1

# Normalize
date > $TMP/info.txt
echo "BRANCH: $GITBRANCH ($(date +%Y%m%d))" >> $TMP/info.txt

if [[ "$SOCFAMILY" == "g12b" ]]
then
    dd if=$TMP_GIT/bl30/bin/$SOCFAMILY/bl30.bin of=$TMP_GIT/bl30_info.bin bs=$((0x1)) count=$((0x44)) skip=$((0x7420))
    echo "bl30: $(< "$TMP_GIT/bl30_info.bin")" >> $TMP/info.txt
else
    dd if=$TMP_GIT/bl30/bin/$SOCFAMILY/bl30.bin of=$TMP_GIT/bl30_info.bin bs=$((0x1)) count=$((0x44)) skip=$((0x77b4))
    echo "bl30: $(< "$TMP_GIT/bl30_info.bin")" >> $TMP/info.txt
fi

for component in $TMP_GIT/*
do
    if [[ -d $component/.git ]]
    then
        echo "$(basename $component): $(git --git-dir=$component/.git log --pretty=format:%H -1 HEAD)" >> $TMP/info.txt
    fi
done

if [[ "$REFBOARD" == "sm1_bananapim5_v1" ]]
then
    dd if=$TMP_GIT/fip/$SOCFAMILY/aml_ddr.fw of=$TMP_GIT/fw_version.bin bs=$((0x1)) count=$((0x13)) skip=$((0xb225))
    dd if=$TMP_GIT/fip/$SOCFAMILY/aml_ddr.fw of=$TMP_GIT/fw_built.bin bs=$((0x1)) count=$((0x46)) skip=$((0xad78))
    sed -i "s/ :/:/" $TMP_GIT/fw_built.bin | echo "DDR-FIRMWARE: $(< "$TMP_GIT/fw_version.bin")" >> $TMP/info.txt
    echo "$(< "$TMP_GIT/fw_built.bin")" >> $TMP/info.txt
    SOCFAMILY="sm1"
fi

if [[ $# -eq 4 ]]
then
    echo "KEY-POWER: $4" >> $TMP/info.txt
fi

echo "SOC: $SOCFAMILY" >> $TMP/info.txt
echo "BOARD: $REFBOARD" >> $TMP/info.txt
rm -rf ${TMP_GIT}
