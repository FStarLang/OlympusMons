#!/usr/bin/env bash
# Usage: scripts/ci/matrix.sh [<target>...]
#
# Print the build matrix of the Build workflow as JSON: one entry per target
# that is built against the F* package (all of them by default), with the
# time limit it is given (see timeout_of in lib.sh) and the wall clock its
# job needs. The workflow reads this rather than listing the targets itself,
# so that lib.sh stays the only place where the set of projects is written
# down, and so that a run can be asked for a subset of them.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

# FStar is built by its own job, which all of the others depend on.
available=("${TARGETS[@]:1}")
wanted=("${available[@]}")
if [ "$#" -gt 0 ]; then
  wanted=()
  for t in "$@"; do
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
  limit=$(timeout_of "$t")
  # The job needs more wall clock than the build itself: checking out, and
  # collecting and uploading the logs afterwards.
  printf '%s{"target":"%s","timeout":"%s","job_minutes":%d}' \
    "$sep" "$t" "$limit" "$(( $(timeout_secs "$limit") / 60 + 20 ))"
  sep=,
done
printf ']\n'
