#!/usr/bin/env bash
# Usage: scripts/status.sh [--markdown]
#
# Summarize the last build of each target, and whether it was built from
# the commit currently recorded in hashes.txt. --markdown prints a table for
# a GitHub Actions job summary, with each target linked to its build log.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

markdown=0
[ "${1:-}" = --markdown ] && markdown=1

icon_of () {
  case "$1" in
    ok)      echo ':white_check_mark:' ;;
    TIMEOUT) echo ':hourglass:' ;;
    FAILED)  echo ':x:' ;;
    *)       echo ':heavy_minus_sign:' ;;
  esac
}

if [ "$markdown" = 1 ]; then
  echo '| | Target | Result | Commit | Time |'
  echo '|---|---|---|---|---|'
else
  printf '%-18s %-7s %-13s %-9s %s\n' TARGET RESULT COMMIT TIME NOTE
fi

for t in "${TARGETS[@]}"; do
  p=${t%-ci}
  f=$OLYMPUS_WORK/status/$t
  if [ -f "$f" ]; then
    read -r result rev secs < "$f"
  else
    result='not run' rev='' secs=''
  fi
  note=
  if [ -n "$rev" ] && [ "$rev" != "$(hash_of "$p")" ]; then
    note='(not the commit in hashes.txt)'
  fi
  if [ "$markdown" = 1 ]; then
    commit='&mdash;'
    [ -n "$rev" ] && commit="[\`${rev:0:12}\`](https://github.com/$(repo_of "$p")/commit/$rev)"
    time='&mdash;'
    [ -n "$secs" ] && time=$(duration "$secs")
    printf '| %s | %s | %s | %s | %s |\n' \
      "$(icon_of "$result")" "$t" "$result${note:+ $note}" "$commit" "$time"
  else
    printf '%-18s %-7s %-13s %-9s %s\n' "$t" "$result" "${rev:0:12}" \
      "${secs:+$(duration "$secs")}" "$note"
  fi
done
