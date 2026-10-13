#!/usr/bin/env bash
# Usage: scripts/setup.sh
#
# One-time setup: an opam switch with the OCaml packages that F* and the
# projects need, and the Z3 versions that they use (in _work/z3). The opam
# switch is not made the current one.

source "$(dirname "$0")/lib.sh"

if ! opam switch list --short | grep -qx "$OLYMPUS_OPAM_SWITCH"; then
  opam switch create -y "$OLYMPUS_OPAM_SWITCH" 5.3.0 --no-switch
fi
"$OLYMPUS_ROOT/scripts/checkout.sh" FStar
opam install -y --switch="$OLYMPUS_OPAM_SWITCH" --deps-only \
  "$(src_dir FStar)/fstar.opam"
# Libraries used by the projects' own OCaml code.
opam install -y --switch="$OLYMPUS_OPAM_SWITCH" \
  domainslib hex re ctypes sha sexplib

mkdir -p "$Z3_BIN"
"$(src_dir FStar)/.scripts/get_fstar_z3.sh" "$Z3_BIN"
