#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for script in build_m5 build_odroidc4 build_radxa0 build_radxa02 build_radxa02pro; do
    cd "$SCRIPT_DIR"
    "${SCRIPT_DIR}/${script}.sh"
done
