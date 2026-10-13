#!/usr/bin/env bash
# pal: its CI (.github/workflows/ci.yml) runs `make` and `make test`. Its
# Pulse library is checked with whichever fstar.exe is first in PATH, which
# olympus_env makes the OlympusMons one.

source "$(dirname "$0")/../lib.sh"
olympus_env
# pal runs F* through its own wrapper (opt/run-fstar.sh, which adds its
# Pulse library to the include path), unless FSTAR_EXE says otherwise.
unset FSTAR_EXE
cd "$(src_dir pal)"

pmake
pmake test
