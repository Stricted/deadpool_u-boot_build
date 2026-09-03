#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

SOC=sm1
BOARD=sm1_bananapim5_v1

if [ "${FORCE_RECOVERY:-}" == "true" ]; then
    ./collect-m5_binaries-git-refboard.sh "$SOC" "$BOARD" board/amlogic/defconfigs/fragments/recovery.cfg
elif [ "${CONSOLE_ENABLED:-}" == "true" ]; then
    ./collect-m5_binaries-git-refboard.sh "$SOC" "$BOARD" board/amlogic/defconfigs/fragments/console.cfg
else
    ./collect-m5_binaries-git-refboard.sh "$SOC" "$BOARD"
fi
