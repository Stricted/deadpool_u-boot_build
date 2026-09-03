#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

BOARD=g12b_radxa02pro_v1

if [ "${FORCE_RECOVERY:-}" == "true" ]; then
    ./build.sh "$BOARD" board/amlogic/defconfigs/fragments/recovery.cfg
    VARIANT=recovery
elif [ "${CONSOLE_ENABLED:-}" == "true" ]; then
    ./build.sh "$BOARD" board/amlogic/defconfigs/fragments/console.cfg
    VARIANT=console
else
    ./build.sh "$BOARD"
    VARIANT=base
fi

./generate-bins-new.sh fip-radxa02-220427 ../u-boot/build/u-boot.bin "${BOARD}-${VARIANT}"
