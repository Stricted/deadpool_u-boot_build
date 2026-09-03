#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

BOARD=sm1_odroidc4_v1

if [ "${FORCE_RECOVERY:-}" == "true" ]; then
    ./build.sh "$BOARD" board/amlogic/defconfigs/fragments/recovery.cfg
elif [ "${CONSOLE_ENABLED:-}" == "true" ]; then
    ./build.sh "$BOARD" board/amlogic/defconfigs/fragments/console.cfg
else
    ./build.sh "$BOARD"
fi

./generate-bins-new.sh fip-collect-g12a-odroidc4-odroidg12-v2015.01-20210623-153349 ../u-boot/build/u-boot.bin
