#!/usr/bin/env bash
# Usage: scripts/ci/check.sh <target>...
#
# Exit non-zero unless every one of the given targets was built successfully
# in this run, naming those that were not. This is the single check that
# says whether the invariant of hashes.txt still holds.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

bad=()
for t in "$@"; do
  if [ -f "$OLYMPUS_WORK/status/$t" ]; then
    read -r result _ < "$OLYMPUS_WORK/status/$t"
  else
    result='did not run'
  fi
  [ "$result" = ok ] || bad+=("$t ($result)")
done

if [ "${#bad[@]}" -gt 0 ]; then
  printf -v list '%s, ' "${bad[@]}"
  echo "::error::${list%, }"
  exit 1
fi
msg "all $# targets succeeded: $*"
