#!/usr/bin/env bash
# Usage: scripts/nightly/publish.sh <candidate-hashes> <fixed-dir> <base-sha>
#
# Everything works with the commits in <candidate-hashes>, apart from the
# projects that were fixed: <fixed-dir>/<project>.hash has the commit of the
# fix, which replaces the candidate. Record the result in hashes.txt, as a
# commit that the caller pushes (after pushing the fixes). Run in a checkout
# of OlympusMons (of main).
#
# Refuses if hashes.txt has changed since <base-sha>, the commit that the
# nightly started from: the run then tested something other than what would
# be replaced. Run it again.

set -euo pipefail

candidate=${1:?usage: publish.sh <candidate-hashes> <fixed-dir> <base-sha>}
fixed=${2:?}
base=${3:?}

if [ "$(git show "$base:hashes.txt")" != "$(cat hashes.txt)" ]; then
  echo "hashes.txt has changed since this run started ($base); not publishing." >&2
  echo "The next run starts from the new one." >&2
  exit 1
fi

cp hashes.txt /tmp/olympus-old-hashes.$$
cp "$candidate" hashes.txt
notes=''
for f in "$fixed"/*.hash; do
  [ -e "$f" ] || continue
  p=$(basename "$f" .hash)
  new=$(cat "$f")
  sed -E -i "s/^($p):[0-9a-f]+/\1:$new/" hashes.txt
  notes="$notes
- $p: fixed by Copilot, on its olympus branch"
done

if git diff --quiet -- hashes.txt; then
  echo "hashes.txt is already up to date: nothing to publish."
  rm -f /tmp/olympus-old-hashes.$$
  exit 0
fi

table=$(
  while IFS=: read -r p new; do
    old=$(sed -e 's/#.*//' "/tmp/olympus-old-hashes.$$" | awk -F: -v p="$p" '$1 == p { print $2 }')
    [ "$old" = "$new" ] && continue
    printf '%s: %s -> %s\n' "$p" "${old:0:12}" "${new:0:12}"
  done < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' hashes.txt)
)
rm -f /tmp/olympus-old-hashes.$$

git diff -- hashes.txt
git -c user.name='OlympusMons nightly' \
    -c user.email='olympusmons-nightly@users.noreply.github.com' \
    commit -q -m "Nightly upgrade

All projects were built from scratch with these commits:

$table
${notes:+
$notes
}
Run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-FStarLang/OlympusMons}/actions/runs/${GITHUB_RUN_ID:-0}" \
    -- hashes.txt
git log -1 --stat
