#!/usr/bin/env bash
# pal: its CI (.github/workflows/ci.yml) runs `make` and `make test`. Its
# Pulse library is checked with whichever fstar.exe is first in PATH, which
# olympus_env makes the OlympusMons one.

source "$(dirname "$0")/../lib.sh"
olympus_env
cd "$(src_dir pal)"

pmake
pmake test
