# Common definitions for the OlympusMons scripts. Source this file, do not
# execute it.

set -euo pipefail

OLYMPUS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OLYMPUS_WORK=${OLYMPUS_WORK:-$OLYMPUS_ROOT/_work}
OLYMPUS_HASHES=${OLYMPUS_HASHES:-$OLYMPUS_ROOT/hashes.txt}
OLYMPUS_OPAM_SWITCH=${OLYMPUS_OPAM_SWITCH:-olympus}
JOBS=${JOBS:-$(nproc)}

# The F* package (bin/fstar.exe, bin/krml, lib/...) built from the recorded
# FStar commit. All downstream projects are built against it.
FSTAR_PKG=$OLYMPUS_WORK/fstar
# A snapshot of the parts of the F* source tree (at the same commit) that
# some projects need: Pulse's makefile library and examples.
FSTAR_SRC=$OLYMPUS_WORK/fstar-src
# Z3 binaries (z3-4.8.5, z3-4.13.3, ...) as fetched by F*'s get_fstar_z3.sh.
Z3_BIN=$OLYMPUS_WORK/z3

PROJECTS=(FStar everparse pal kuiper pulse-verified-gc AlgoStar hacl-pulse)

repo_of () {
  case "$1" in
    FStar)             echo FStarLang/FStar ;;
    everparse)         echo project-everest/everparse ;;
    pal)               echo FStarLang/pal ;;
    kuiper)            echo FStarLang/kuiper ;;
    pulse-verified-gc) echo FStarLang/pulse-verified-gc ;;
    AlgoStar)          echo FStarLang/AlgoStar ;;
    hacl-pulse)        echo FStarLang/hacl-pulse ;;
    *) echo "unknown project: $1" >&2; return 1 ;;
  esac
}

# The commit recorded for project $1 in hashes.txt.
hash_of () {
  local h
  h=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$OLYMPUS_HASHES" \
      | awk -F: -v p="$1" '$1 == p { print $2 }')
  if [ -z "$h" ]; then
    echo "no hash recorded for $1 in $OLYMPUS_HASHES" >&2
    return 1
  fi
  echo "$h"
}

src_dir () { echo "$OLYMPUS_WORK/src/$1"; }

# git, authenticating HTTPS through the GitHub CLI when it is available
# (some of the repositories are private).
git_auth () {
  if command -v gh > /dev/null; then
    git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"
  else
    git "$@"
  fi
}

# OCaml (the dedicated opam switch) and Z3. This is all F* itself needs.
base_env () {
  if [ -n "$OLYMPUS_OPAM_SWITCH" ]; then
    eval "$(opam env --switch="$OLYMPUS_OPAM_SWITCH" --set-switch)"
  fi
  export PATH="$Z3_BIN:$PATH"
  # Builds must succeed without proof recovery or other leniency.
  unset OTHERFLAGS FSTAR_EXE FSTAR_HOME FSTAR_ROOT KRML_EXE KRML_HOME PULSE_ROOT
}

# Environment for building a downstream project against the OlympusMons F*.
# This overrides whatever F*/KaRaMeL/Pulse the projects would otherwise pick
# up (submodules, nightlies, pinned hashes, ...).
olympus_env () {
  base_env
  if [ ! -x "$FSTAR_PKG/bin/fstar.exe" ]; then
    echo "no F* package at $FSTAR_PKG; build FStar first" >&2
    return 1
  fi
  export PATH="$FSTAR_PKG/bin:$PATH"
  export FSTAR_EXE="$FSTAR_PKG/bin/fstar.exe"
  export KRML_EXE="$FSTAR_PKG/bin/krml"
  export FSTAR_HOME="$FSTAR_PKG"
  export FSTAR_ROOT="$FSTAR_PKG"
  # A KaRaMeL source tree layout within the package (see build/FStar.sh).
  export KRML_HOME="$FSTAR_PKG/karamel"
  export PULSE_ROOT="$FSTAR_SRC/pulse"
}

# make, in parallel. Under a parallel OlympusMons make, use its jobserver
# rather than starting another $JOBS-wide build.
pmake () {
  if [[ " ${MAKEFLAGS:-} " == *jobserver* ]]; then
    make "$@"
  else
    make -j"$JOBS" "$@"
  fi
}

msg () { printf '[olympus] %s\n' "$*" >&2; }
