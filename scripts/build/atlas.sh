#!/usr/bin/env bash
# Atlas: the targets of its CI (.github/workflows/ci.yml), but the interop
# tests, which need system services (tftpd, lrzsz) that the runner does not
# have. Built against the trees that the EverParse and hacl-pulse builds
# left (deps_of in lib.sh) instead of the toolchain that its setup.sh
# builds in tools/: QuackyDucky and LowParse from EverParse, and the
# extracted C, the checked files and Hacl.cui from hacl-pulse.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"
olympus_env
cd "$(src_dir atlas)"

vars=(
  EVERPARSE_HOME="$(src_dir everparse)"
  HACL_PULSE_HOME="$(src_dir hacl-pulse)"
  FSTAR_EXE="$FSTAR_EXE" FSTAR_HOME="$FSTAR_PKG" FSTAR_SOURCE_ROOT="$FSTAR_SRC"
  KRML_EXE="$KRML_EXE" KRML_HOME="$KRML_HOME"
  Z3_DIR="$Z3_BIN" Z3_VERSION="$OLYMPUS_Z3_VERSION"
  # It checks that tools/everparse is at the commit it pins; ours is not.
  CHECK_EVERPARSE_PIN=0
)

pmake "${vars[@]}" test
pmake "${vars[@]}" -C calc_sample test-c
pmake "${vars[@]}" -C ftp_sample
pmake "${vars[@]}" -C ymodem_sample vloop-test
pmake "${vars[@]}" -C tftp_sample vloop-test
pmake "${vars[@]}" -C http_sample vloop-tests
