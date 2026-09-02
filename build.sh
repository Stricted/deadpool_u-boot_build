#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

set -o xtrace

# The goal of this script is gather all binaries provides by AML in order to generate
# our final u-boot image from the u-boot.bin (bl33)
#
# Some binaries come from the u-boot vendor kernel (bl21, acs, bl301)
# Others from the buildroot package (aml_encrypt tool, bl2.bin, bl30)

function usage() {
    echo "Usage: $0 [openlinux branch] [refboard]"
}

if [[ $# -lt 2 ]]
then
    usage
    exit 22
fi

GITBRANCH=${1}
REFBOARD=${2}

# path to clone the openlinux repos
TMP_GIT=$(pwd)/out

# U-Boot
git clone --depth=2 https://github.com/Stricted/deadpool_u-boot.git -b $GITBRANCH $TMP_GIT/u-boot

mkdir $TMP_GIT/gcc-linaro-aarch64-none-elf
wget -qO- https://mirror.twds.com.tw/armbian-dl/_toolchain/gcc-linaro-aarch64-none-elf-4.8-2013.11_linux.tar.xz | tar -xJ --strip-components=1 -C $TMP_GIT/gcc-linaro-aarch64-none-elf
mkdir $TMP_GIT/gcc-linaro-arm-none-eabi
wget -qO- https://mirror.twds.com.tw/armbian-dl/_toolchain/gcc-linaro-arm-none-eabi-4.8-2014.04_linux.tar.xz | tar -xJ --strip-components=1 -C $TMP_GIT/gcc-linaro-arm-none-eabi


sed -i "s,/opt/gcc-.*/bin/,," $TMP_GIT/u-boot/Makefile
(
    cd $TMP_GIT/u-boot
    make ${REFBOARD}_defconfig
    PATH=$TMP_GIT/gcc-linaro-aarch64-none-elf/bin:$TMP_GIT/gcc-linaro-arm-none-eabi/bin:$PATH CROSS_COMPILE=aarch64-none-elf- make -j8 > /dev/null
)

#rm -rf ${TMP_GIT}
