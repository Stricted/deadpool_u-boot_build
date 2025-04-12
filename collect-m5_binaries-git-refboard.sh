#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset
set -o xtrace
# The goal of this script is gather all binaries provides by AML in order to generate
# our final u-boot image from the u-boot.bin (bl33)
#
# Some binaries come from the u-boot vendor (bl2.bin, bl30, bl31, aml_encrypt tool, ddr firmware)
function usage() {
    echo "Usage: $0 [u-boot branch] [soc] [refboard] [revision]"
}
if [[ $# -lt 4 ]]
then
    usage
    exit 22
fi
GITBRANCH=${1}
SOCFAMILY=${2}
REFBOARD=${3}
case ${4} in
    0|1|2) REVISION=${4} ;;
    *) echo "Undefined argument, use [2] for M5 Rayson-DDR, [1] for M5 ICMAX-DDR, [0] for other board"
       exit ;;
esac
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
bl2="bootloader/uboot-repo/bl2/bin"
bl30="bootloader/uboot-repo/bl30/bin"
bl31="bootloader/uboot-repo/bl31_1.3/bin"
fw="bootloader/uboot-repo/fip"
ddr="bootloader/uboot-repo/fip/tools/ddr_parse"
BIN_LIST="$bl2/$SOCFAMILY/bl2.bin \
          $bl30/$SOCFAMILY/bl30.bin \
	  $bl31/$SOCFAMILY/bl31.bin \
	  $bl31/$SOCFAMILY/bl31.img \
	  $fw/$SOCFAMILY/aml_encrypt_$SOCFAMILY \
          $fw/$SOCFAMILY/*.fw"
# path to clone the u-boot repos
TMP_GIT=$(mktemp -d)
TMP="fip-collect-${SOCFAMILY}-${REFBOARD}-${GITBRANCH}-$(date +%Y%m%d-%H%M%S)"
mkdir $TMP
# M5 (Rev. 1): Use old BPI-S905X3 master branch to checkout FIP binaries
commit="a538717a004e5a99927a755db5f5643c31caf6ce"
# FIP-binaries & ddr_parse src
get_src () {
    local GITBRANCH="master"
    if [[ "$REVISION" != "1" ]]
    then
        git clone -n --depth=1 --filter=tree:0 https://github.com/BPI-SINOVOIP/BPI-S905X3-Android9.git -b $GITBRANCH $TMP_GIT/FIP
        (
            cd $TMP_GIT/FIP
            git sparse-checkout set --no-cone /$bl2/$SOCFAMILY /$bl30/$SOCFAMILY /$bl31/$SOCFAMILY /$fw/$SOCFAMILY /$ddr
            git checkout
        )
    else
        git clone -n --depth=1 --filter=tree:0 https://github.com/BPI-SINOVOIP/BPI-S905X3-Android9.git -b $GITBRANCH $TMP_GIT/FIP
        (
            cd $TMP_GIT/FIP
            git sparse-checkout set --no-cone /$bl2/$SOCFAMILY /$bl30/$SOCFAMILY /$bl31/$SOCFAMILY /$fw/$SOCFAMILY /$ddr
            git config --global advice.detachedHead false && git checkout $commit
        )
    fi
}
get_src "$@"
# M5 (Rev. 2): Use old BPI-S905X3 master branch to checkout bl30.bin, as the new blob leads to "Undefined instructions" crash
get_bl30 () {
    local GITBRANCH="master"
    git clone -n --depth=1 --filter=tree:0 https://github.com/BPI-SINOVOIP/BPI-S905X3-Android9.git -b $GITBRANCH $TMP_GIT/bl30
    (
        cd $TMP_GIT/bl30
        git sparse-checkout set --no-cone /$bl30/$SOCFAMILY
        git config --global advice.detachedHead false && git checkout $commit
    )
}
if [[ "$REFBOARD" == "sm1_bananapim5_v1" ]]
then
    get_bl30 "$@"
    if [[ "$REVISION" == "2" ]]
    then
        cp $TMP_GIT/bl30/$bl30/$SOCFAMILY/* $TMP/
    fi
fi
# U-Boot
git clone --depth=2 https://github.com/Stricted/deadpool_u-boot.git -b $GITBRANCH $TMP_GIT/u-boot
mkdir -p $TMP_GIT/u-boot/fip/tools
mkdir $TMP_GIT/gcc-linaro-aarch64-none-elf
wget -qO- https://releases.linaro.org/archive/13.11/components/toolchain/binaries/gcc-linaro-aarch64-none-elf-4.8-2013.11_linux.tar.xz | tar -xJ --strip-components=1 -C $TMP_GIT/gcc-linaro-aarch64-none-elf
mkdir $TMP_GIT/gcc-linaro-arm-none-eabi
wget -qO- https://releases.linaro.org/archive/13.11/components/toolchain/binaries/gcc-linaro-arm-none-eabi-4.8-2013.11_linux.tar.xz | tar -xJ --strip-components=1 -C $TMP_GIT/gcc-linaro-arm-none-eabi
sed -i "s,/opt/gcc-.*/bin/,," $TMP_GIT/u-boot/Makefile
cp -r $TMP_GIT/FIP/$ddr $TMP_GIT/u-boot/fip/tools/
(
    cd $TMP_GIT/u-boot
    make ${REFBOARD}_defconfig
    PATH=$TMP_GIT/gcc-linaro-aarch64-none-elf/bin:$TMP_GIT/gcc-linaro-arm-none-eabi/bin:$PATH CROSS_COMPILE=aarch64-none-elf- make -j8 > /dev/null
    cd fip/tools/ddr_parse && make clean && make
    ./parse ../../../build/board/amlogic/*/firmware/acs.bin
)
cp $TMP_GIT/u-boot/build/board/amlogic/*/firmware/acs.bin $TMP/
cp $TMP_GIT/u-boot/build/scp_task/bl301.bin $TMP/
# FIP/BLX
if [[ "$REVISION" == "2" ]]
then
    MOD_LIST="${BIN_LIST//"$bl30/$SOCFAMILY/bl30.bin"/}"
    BIN_LIST="$MOD_LIST"
fi
echo $BIN_LIST
for item in $BIN_LIST
do
    BIN=$(echo $item)
    cp $TMP_GIT/FIP/$BIN ${TMP}
done
# Normalize
mv $TMP_GIT/FIP/$fw/$SOCFAMILY/aml_encrypt_$SOCFAMILY $TMP/aml_encrypt
date > $TMP/info.txt
echo "BRANCH: $GITBRANCH ($(date +%Y%m%d))" >> $TMP/info.txt
if [[ "$REFBOARD" == "sm1_bananapim5_v1" ]]
then
    dd if=$TMP_GIT/bl30/$bl30/$SOCFAMILY/bl30.bin of=$TMP_GIT/bl30_info.bin bs=$((0x1)) count=$((0x44)) skip=$((0x77b4))
    echo "bl30: $(< "$TMP_GIT/bl30_info.bin")" >> $TMP/info.txt
fi
for component in $TMP_GIT/*
do
    if [[ -d $component/.git ]]
    then
        echo "$(basename $component): $(git --git-dir=$component/.git log --pretty=format:%H -1 HEAD)" >> $TMP/info.txt
    fi
done

if [[ "$REVISION" != "1" ]]
then
    dd if=$TMP_GIT/FIP/$fw/$SOCFAMILY/aml_ddr.fw of=$TMP_GIT/fw_version.bin bs=$((0x1)) count=$((0x13)) skip=$((0xb225))
    dd if=$TMP_GIT/FIP/$fw/$SOCFAMILY/aml_ddr.fw of=$TMP_GIT/fw_built.bin bs=$((0x1)) count=$((0x46)) skip=$((0xad78))
else
    dd if=$TMP_GIT/FIP/$fw/$SOCFAMILY/aml_ddr.fw of=$TMP_GIT/fw_version.bin bs=$((0x1)) count=$((0x13)) skip=$((0xb5ad))
    dd if=$TMP_GIT/FIP/$fw/$SOCFAMILY/aml_ddr.fw of=$TMP_GIT/fw_built.bin bs=$((0x1)) count=$((0x46)) skip=$((0xb100))
fi
if [[ "$REFBOARD" == "sm1_bananapim5_v1" ]]
then
    sed -i 's/ :/:/' $TMP_GIT/fw_built.bin | echo "DDR-FIRMWARE: $(< "$TMP_GIT/fw_version.bin")" >> $TMP/info.txt
    echo "$(< "$TMP_GIT/fw_built.bin")" >> $TMP/info.txt
    echo "BOARD: $REFBOARD (Rev. $REVISION)" >> $TMP/info.txt
    SOCFAMILY="sm1"
fi
echo "SOC: $SOCFAMILY" >> $TMP/info.txt
if [[ "$REVISION" == "0" ]]
then
    echo "BOARD: $REFBOARD" >> $TMP/info.txt
fi
echo "export SOCFAMILY=$SOCFAMILY" > $TMP/soc-var.sh
rm -rf ${TMP_GIT}
