#!/usr/bin/env bash
# F*'s own CI target.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"
base_env
cd "$(src_dir FStar)"

# Cherry's C output needs GCC 15 or later (F*'s doc/ref/cherry.md, "Tail
# calls"); F*'s CI passes gcc-15 as CHERRY_CC, as we do when it is installed.
if [ -z "${CHERRY_CC:-}" ] && command -v gcc-15 >/dev/null; then
  export CHERRY_CC=gcc-15
fi
if [ -z "${CHERRY_CXX:-}" ] && command -v g++-15 >/dev/null; then
  export CHERRY_CXX=g++-15
fi

pmake ci
