#!/usr/bin/env bash
# EverParse: the targets of its Linux CI (.github/workflows/ci.yml, minus
# the ADMIT_* shortcuts that CI uses to split the work across jobs, so
# everything is verified here) and of cbor.yml.

source "$(dirname "$0")/../lib.sh"
olympus_env
cd "$(src_dir everparse)"

export EVERPARSE_USE_OPAMROOT=1
export EVERPARSE_USE_FSTAR_EXE=1
export EVERPARSE_USE_KRML_EXE=1
export DICE_HOME="$PULSE_ROOT/share/pulse/examples/dice"
export EVERPARSE_TEST_32BIT=1

pmake lowparse \
  3d-test quackyducky-test lowparse-test asn1-test \
  cddl cbor-verify \
  cddl-test cbor-test cose-test \
  EVERPARSE_CHECK_DIFF=1

pmake -f nofstar.Makefile test-nofstar
