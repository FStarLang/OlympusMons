#!/usr/bin/env bash
# EverParse: the targets of its Linux CI (.github/workflows/ci.yml, minus
# the ADMIT_* shortcuts that CI uses to split the work across jobs, so
# everything is verified here) and of cbor.yml.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"
olympus_env
cd "$(src_dir everparse)"

# The one exception to "F* provides KaRaMeL": EverParse's 3D code generation
# uses krml features (-no-inline-type-abbrev, -finitialize-locals,
# -fhoist-locals, -goto_for_early_return, ...) that are only on a KaRaMeL
# branch, not in F*'s KaRaMeL submodule. So EverParse uses the krml of the
# KaRaMeL commit that it pins in opt/hashes.Makefile (only the OCaml krml
# executable is built; it reads the .krml files of the recorded F*).
krml_rev=$(sed -n 's/^karamel_hash *:= *\([0-9a-f]*\).*/\1/p' opt/hashes.Makefile)
[ -n "$krml_rev" ] || { echo "no karamel_hash in opt/hashes.Makefile" >&2; exit 1; }
"$OLYMPUS_ROOT/scripts/checkout.sh" everparse-karamel "$krml_rev"
kd=$(src_dir everparse-karamel)
if [ "$(cat "$kd/out/.olympus-rev" 2> /dev/null)" != "$krml_rev" ]; then
  rm -rf "$kd/out"
  make -C "$kd" LOWSTAR=false
  echo "$krml_rev" > "$kd/out/.olympus-rev"
fi
export KRML_HOME="$kd"
export KRML_EXE="$kd/out/bin/krml"

export EVERPARSE_USE_OPAMROOT=1
export EVERPARSE_USE_FSTAR_EXE=1
export EVERPARSE_USE_KRML_EXE=1
export DICE_HOME="$PULSE_ROOT/share/pulse/examples/dice"
export EVERPARSE_TEST_32BIT=1
# The Z3 under test, rather than the one that EverParse pins.
export EVERPARSE_Z3_VERSION=$OLYMPUS_Z3_VERSION

pmake lowparse \
  3d-test quackyducky-test lowparse-test asn1-test \
  cddl cbor-verify \
  cddl-test cbor-test cose-test \
  EVERPARSE_CHECK_DIFF=1 3D_Z3_EXECUTABLE=z3

pmake -f nofstar.Makefile test-nofstar
