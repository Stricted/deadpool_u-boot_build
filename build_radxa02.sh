#!/bin/bash

if [ "${FORCE_RECOVERY}" == "true" ]
then
./build.sh android-tv-13.0.0_r1-recovery-only sm1_radxa02_v1
elif [ "${CONSOLE_ENABLED}" == "true" ]
then
./build.sh android-tv-13.0.0_r1-console sm1_radxa02_v1
else
./build.sh android-tv-13.0.0_r1 sm1_radxa02_v1
fi
./generate-bins-new.sh fip-radxa02-220427 out/u-boot/build/u-boot.bin

rm -rf out
