#!/usr/bin/env bash
# What hacl-pulse's CI (ci.yml, its verify job) runs: its default target
# lints, verifies everything, extracts dist/ (with Custard), compiles it,
# checks its stack frames and runs the C tests. As in its CI, the
# constant-time audit is built but not run: on a busy shared machine its
# timings measure the load, not the code.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"
olympus_env
cd "$(src_dir hacl-pulse)"

pmake FSTAR_EXE="$FSTAR_EXE" TEST_NORUN=test_consttime
