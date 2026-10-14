#!/usr/bin/env bash
# Kuiper: only its `verify` target. Kuiper's extraction to CUDA needs the
# patched F* and KaRaMeL on its own `_kuiper` branches (its FStar/karamel
# submodules), so it is out of scope for OlympusMons; verification must
# work with plain F*.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"
olympus_env
cd "$(src_dir kuiper)"

# Kuiper's marker (gitignored) for "the toolchain is prebuilt": it stops
# verify.mk from building F* from the (uninitialized) submodules. We then
# point it at the OlympusMons F* instead of the one it would install in inst/.
touch .packaged
pmake verify FSTAR_EXE="$FSTAR_EXE" KRML_EXE="$KRML_EXE"
