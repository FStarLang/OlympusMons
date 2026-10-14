#!/usr/bin/env bash
# pulse-verified-gc: the steps of its CI (.github/workflows/verify.yml). The
# steps that CI runs serially are run serially here too.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"
olympus_env
cd "$(src_dir pulse-verified-gc)"

pmake
pmake -C spot
make -j1 extract
make -j1 -C generational snapshot
I=generational/ocaml-integration
make -j1 -C $I setup
make -j1 -C $I/tests test \
  OCAMLC="$PWD/$I/ocaml-4.14-unchanged/_install/bin/ocamlc" \
  VERIFIED_GEN_OCAMLRUN="$PWD/$I/ocaml-4.14-verified-gen/runtime/ocamlrun" \
  UNCHANGED_OCAMLRUN="$PWD/$I/ocaml-4.14-unchanged/runtime/ocamlrun"

# As in its CI, out-of-date snapshots are only a warning.
if ! git diff --quiet -- generational/snapshot/; then
  msg "WARNING: pulse-verified-gc snapshots are out of date:"
  git diff --stat -- generational/snapshot/ >&2
fi
