#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

BOARD=g12a_radxa0_v1

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

./generate-bins-new.sh fip-radxa0-20210802 ../u-boot/build/u-boot.bin "${BOARD}-${VARIANT}"
