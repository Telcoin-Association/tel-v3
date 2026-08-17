#!/usr/bin/env bash
# Compile-if-stale wrapper for mine_vanity_salt.c. All arguments pass through
# to the miner — see ./mine-vanity-salt.sh --help.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v cc >/dev/null 2>&1; then
    echo "error: no C compiler ('cc') on PATH. Install Xcode CLT (xcode-select --install) or gcc/clang." >&2
    exit 1
fi

mkdir -p build
if [[ ! -x build/mine_vanity_salt || mine_vanity_salt.c -nt build/mine_vanity_salt ]]; then
    echo "[build] cc -O3 -std=c11 -Wall -Wextra -pthread mine_vanity_salt.c" >&2
    cc -O3 -std=c11 -Wall -Wextra -pthread -o build/mine_vanity_salt mine_vanity_salt.c
fi

exec build/mine_vanity_salt "$@"
