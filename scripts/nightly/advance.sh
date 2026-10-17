#!/usr/bin/env bash
# Usage: scripts/nightly/advance.sh <new-hashes-file>
#
# Work out the commits that the nightly run tries, and write them to
# <new-hashes-file> in the format of hashes.txt (comments kept). Nothing in
# the repository is changed; the nightly builds against this file
# (OLYMPUS_HASHES) and records it only if everything then works.
#
# * F* moves to the tip of its master branch ($FSTAR_REV, a branch or a
#   commit, overrides this).
# * Every other project moves to the tip of its `olympus` branch, the one
#   that OlympusMons tracks, or if it has none, to the tip of its default
#   branch (a fix, if one is needed, then creates the `olympus` branch).
#
# A project only ever moves forward: if the recorded commit is not an
# ancestor of the new one (someone pinned a side branch, say), it stays
# where it is, and the run says so.
#
# Sets `changed` in $GITHUB_OUTPUT when run by Actions.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

out=${1:?usage: advance.sh <new-hashes-file>}
cp "$OLYMPUS_HASHES" "$out"

# The commit that ref $2 of repository $1 points at, or nothing.
tip () {
  git_net ls-remote "https://github.com/$1.git" "$2" | awk 'NR == 1 { print $1 }'
}

changed=0
printf '%-18s %-12s %-12s %-10s %s\n' PROJECT FROM TO BRANCH NOTE
for p in "${PROJECTS[@]}"; do
  repo=$(repo_of "$p")
  old=$(hash_of "$p")
  branch='' new='' note=''
  if [ "$p" = FStar ] && [[ "${FSTAR_REV:-}" =~ ^[0-9a-f]{40}$ ]]; then
    new=$FSTAR_REV branch='(given)'
  elif [ "$p" = FStar ]; then
    branch=${FSTAR_REV:-master}
    new=$(tip "$repo" "refs/heads/$branch")
  else
    branch=olympus
    new=$(tip "$repo" refs/heads/olympus)
    if [ -z "$new" ]; then
      branch='(default)'
      new=$(tip "$repo" HEAD)
    fi
  fi
  if [ -z "$new" ]; then
    echo "$p: cannot find the commit to advance $repo to ($branch)" >&2
    exit 1
  fi

  if [ "$new" = "$old" ]; then
    note=unchanged
  else
    rel=$(gh api "repos/$repo/compare/$old...$new" --jq .status 2> /dev/null || echo unknown)
    case $rel in
      ahead) changed=1; note=advanced ;;
      *) note="kept: the recorded commit is not behind it ($rel)"; new=$old ;;
    esac
  fi
  sed -E -i "s/^($p):[0-9a-f]+/\1:$new/" "$out"
  printf '%-18s %-12s %-12s %-10s %s\n' "$p" "${old:0:12}" "${new:0:12}" "$branch" "$note"
done

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "changed=$([ "$changed" = 1 ] && echo true || echo false)" >> "$GITHUB_OUTPUT"
fi
msg "candidate hashes written to $out"
