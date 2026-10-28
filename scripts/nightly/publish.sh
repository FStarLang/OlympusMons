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
#
# With REQUIRE_PUSHED=1, also refuses unless every project's commit has been
# pushed to its repository (push-olympus.sh notes it in
# $OLYMPUS_WORK/nightly/pushed): hashes.txt must name commits that can be
# fetched.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

candidate=${1:?usage: publish.sh <candidate-hashes> <fixed-dir> <base-sha>}
fixed=${2:?}
base=${3:?}

if [ "$(git show "$base:hashes.txt")" != "$(cat hashes.txt)" ]; then
  echo "hashes.txt has changed since this run started ($base); not publishing." >&2
  echo "The next run starts from the new one." >&2
  exit 1
fi

if [ "${REQUIRE_PUSHED:-0}" = 1 ]; then
  unpushed=()
  for p in "${PROJECTS[@]:1}"; do
    want=$(OLYMPUS_HASHES=$candidate hash_of "$p")
    [ -f "$fixed/$p.hash" ] && want=$(cat "$fixed/$p.hash")
    [ "$(cat "$OLYMPUS_WORK/nightly/pushed/$p" 2> /dev/null)" = "$want" ] || unpushed+=("$p")
  done
  if [ "${#unpushed[@]}" -gt 0 ]; then
    echo "not pushed to their repositories: ${unpushed[*]}; not publishing." >&2
    exit 1
  fi
fi

cp hashes.txt /tmp/olympus-old-hashes.$$
cp "$candidate" hashes.txt
notes=''
for f in "$fixed"/*.hash; do
  [ -e "$f" ] || continue
  p=$(basename "$f" .hash)
  new=$(cat "$f")
  sed -E -i "s/^($p):[0-9a-f]+/\1:$new/" hashes.txt
done
for p in "${PROJECTS[@]}"; do
  note=''
  if [ "$(rebase_info "$p" result)" = conflict ]; then
    note="its olympus branch did not rebase onto $(rebase_info "$p" branch); Copilot rebased it, and fixed what broke"
  elif [ -e "$fixed/$p.hash" ]; then
    note="fixed by Copilot, on its olympus branch"
  fi
  if [ -n "$note" ] && pr_project "$p"; then
    note="$note, in a pull request"
  fi
  [ -z "$note" ] || notes="$notes
- $p: $note"
done

if git diff --quiet -- hashes.txt; then
  echo "hashes.txt is already up to date: nothing to publish."
  rm -f /tmp/olympus-old-hashes.$$
  exit 0
fi

table=$(
  while IFS=: read -r p new; do
    old=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "/tmp/olympus-old-hashes.$$" | awk -F: -v p="$p" '$1 == p { print $2 }')
    [ "$old" = "$new" ] && continue
    printf '%s: %s -> %s\n' "$p" "${old:0:12}" "${new:0:12}"
  done < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' hashes.txt)
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
