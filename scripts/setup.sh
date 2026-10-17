#!/usr/bin/env bash
# Usage: scripts/setup.sh
#
# One-time setup: an opam switch with the OCaml packages that F* and the
# projects need, and the Z3 that the recorded F* uses (in _work/z3, see
# install-z3.sh). The opam switch is not made the current one.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

# A fresh opam installation (e.g. on a new CI runner), set up as F*'s CI does.
if [ ! -d "${OPAMROOT:-$HOME/.opam}" ]; then
  opam init -y --bare --disable-sandboxing --no-setup
fi
if ! opam switch list --short | grep -qx "$OLYMPUS_OPAM_SWITCH"; then
  opam switch create -y "$OLYMPUS_OPAM_SWITCH" 5.3.0 --no-switch
fi
"$OLYMPUS_ROOT/scripts/checkout.sh" FStar
opam install -y --switch="$OLYMPUS_OPAM_SWITCH" --deps-only \
  "$(src_dir FStar)/fstar.opam"
# Libraries used by the projects' own OCaml code.
opam install -y --switch="$OLYMPUS_OPAM_SWITCH" \
  domainslib hex re ctypes sha sexplib

"$OLYMPUS_ROOT/scripts/install-z3.sh"
