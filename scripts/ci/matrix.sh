#!/usr/bin/env bash
# Usage: scripts/ci/matrix.sh [--dependents] [<target>...]
#        scripts/ci/matrix.sh --minutes
#
# Print the build matrix of the Build workflow as JSON: one entry per target
# that is built against the F* package (all of them by default, and with
# their dependencies when some are named), with the time limit it is given
# (see timeout_of in lib.sh) and the wall clock its job needs. The workflow
# reads this rather than listing the targets itself, so that lib.sh stays
# the only place where the set of projects is written down, and so that a
# run can be asked for a subset of them.
#
# The targets that depend on other projects (deps_of in lib.sh) are built
# after the others, by a job of their own: without --dependents, the matrix
# has the others, and with it, those.
#
# --minutes prints, instead, the wall clock that each target's job in the
# Nightly needs, as a JSON object: it builds the target, and if that fails,
# has Copilot repair it (for at most OLYMPUS_COPILOT_TIMEOUT, see fix.sh)
# and builds the repair from scratch.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

# FStar is built by its own job, which all of the others depend on.
available=("${TARGETS[@]:1}")

# The job needs more wall clock than the build itself: checking out, and
# collecting and uploading the logs afterwards.
job_minutes () { echo $(( $(timeout_secs "$(timeout_of "$1")") / 60 + 20 )); }

if [ "${1:-}" = --minutes ]; then
  copilot=$(( $(timeout_secs "${OLYMPUS_COPILOT_TIMEOUT:-12h}") / 60 ))
  for t in "${available[@]}"; do
    printf '{"%s":%d}\n' "$t" "$(( 2 * $(job_minutes "$t") + copilot + 20 ))"
  done | jq -sc add
  exit 0
fi

dependents=0
if [ "${1:-}" = --dependents ]; then dependents=1; shift; fi

wanted=("${available[@]}")
if [ "$#" -gt 0 ]; then
  asked=("$@")
  # With their dependencies, which are built in the same run.
  for t in "$@"; do
    # shellcheck disable=SC2207  # deps_of prints project names
    asked+=($(deps_of "$t"))
  done
  wanted=()
  for t in "${asked[@]}"; do
    # F* is always built, by the job that the others depend on; asking for
    # it by name (alone, to build only F*) adds nothing to the matrix.
    if [ "$t" = FStar ]; then continue; fi
    # Twice would be two jobs building one tree at the same time.
    case " ${wanted[*]:-} " in
      *" $t "*) continue ;;
    esac
    case " ${available[*]} " in
      *" $t "*) wanted+=("$t") ;;
      *) echo "no such target: $t (expected one of: FStar ${available[*]})" >&2
         exit 1 ;;
    esac
  done
fi

sep=
printf '['
for t in "${wanted[@]}"; do
  if [ -n "$(deps_of "$t")" ]; then has_deps=1; else has_deps=0; fi
  [ "$has_deps" = "$dependents" ] || continue
  printf '%s{"target":"%s","timeout":"%s","job_minutes":%d}' \
    "$sep" "$t" "$(timeout_of "$t")" "$(job_minutes "$t")"
  sep=,
done
printf ']\n'
