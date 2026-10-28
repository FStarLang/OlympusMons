#!/usr/bin/env bash
# Usage: scripts/nightly/advance.sh <new-hashes-file>
#
# Work out the commits that the nightly run tries, and write them to
# <new-hashes-file> in the format of hashes.txt (comments kept), starting
# from $OLYMPUS_HASHES (hashes.txt). Nothing in the repository is changed;
# the nightly builds against this file (OLYMPUS_HASHES) and records it only
# if everything then works.
#
# * F* moves to the tip of its master branch ($FSTAR_REV, a branch or a
#   commit, overrides this), and only ever forward: if the recorded commit
#   is not an ancestor of the new one, it stays where it is.
# * Every other project moves to the tip of its default branch, with the
#   commits of its `olympus` branch (if it has one) rebased on top of it, so
#   that the `olympus` branch stays a few commits on top of upstream instead
#   of accumulating merges. The rebase is made locally, in the project's
#   clone (in a worktree of its own, so the tree is left as it is); nothing
#   is pushed. The rebased commit is kept alive by refs/olympus/candidate.
#   If the rebase stops with conflicts, the candidate is the `olympus` tip
#   as it is, the project is not built, and its Fix job has Copilot do the
#   rebase (see run.sh and fix.sh).
#
# What was found for each project (its default branch and tip, the `olympus`
# tip, how the rebase went) is left in $OLYMPUS_WORK/nightly/rebase/<project>
# for the later jobs (see rebase_info in lib.sh), with the output of the
# rebase in <project>.rebase.log.
#
# Sets `changed` in $GITHUB_OUTPUT when run by Actions.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

out=${1:?usage: advance.sh <new-hashes-file>}
cp "$OLYMPUS_HASHES" "$out"
state=$OLYMPUS_WORK/nightly/rebase
rm -rf "$state"
mkdir -p "$state"

# The commit that ref $2 of repository $1 points at, or nothing.
tip () {
  git_net ls-remote "https://github.com/$1.git" "$2" | awk 'NR == 1 { print $1 }'
}

# The name of the default branch of repository $1.
default_branch () {
  git_net ls-remote --symref "https://github.com/$1.git" HEAD \
    | awk '$1 == "ref:" { sub("^refs/heads/", "", $2); print $2; exit }'
}

# Clone project $1 if need be, and fetch all of its branches and the tags
# that keep the old `olympus` commits alive (see push-olympus.sh).
fetch_project () {
  local p=$1 src url
  src=$(src_dir "$p")
  url="https://github.com/$(repo_of "$p").git"
  if [ ! -d "$src/.git" ]; then
    mkdir -p "$(dirname "$src")"
    git_net clone -q "$url" "$src" || { rm -rf "$src"; return 1; }
  fi
  git_net -C "$src" fetch -q --prune origin \
    '+refs/heads/*:refs/remotes/origin/*' '+refs/tags/olympus/*:refs/tags/olympus/*'
}

# Rebase commit $3 onto commit $2 in the clone of project $1. Prints the
# result, or returns 1 (with the rebase undone) if it stops with conflicts.
rebase_onto () {
  local p=$1 onto=$2 head=$3 src wt rc=0
  src=$(src_dir "$p")
  wt=$state/$p.tree
  git -C "$src" worktree prune
  git -C "$src" worktree add -q --detach "$wt" "$head" > /dev/null
  if git -C "$wt" "${NIGHTLY_GIT_ID[@]}" rebase "$onto" > "$state/$p.rebase.log" 2>&1; then
    git -C "$wt" rev-parse HEAD
  else
    rc=1
    git -C "$wt" status --short >> "$state/$p.rebase.log" 2>&1 || true
    git -C "$wt" rebase --abort > /dev/null 2>&1 || true
  fi
  git -C "$src" worktree remove --force "$wt"
  return "$rc"
}

changed=0
printf '%-18s %-12s %-12s %-10s %s\n' PROJECT FROM TO BRANCH NOTE
for p in "${PROJECTS[@]}"; do
  repo=$(repo_of "$p")
  old=$(hash_of "$p")
  branch='' new='' note=''
  if [ "$p" = FStar ]; then
    if [[ "${FSTAR_REV:-}" =~ ^[0-9a-f]{40}$ ]]; then
      new=$FSTAR_REV branch='(given)'
    else
      branch=${FSTAR_REV:-master}
      new=$(tip "$repo" "refs/heads/$branch")
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
        ahead) note=advanced ;;
        *) note="kept: the recorded commit is not behind it ($rel)"; new=$old ;;
      esac
    fi
  else
    src=$(src_dir "$p")
    branch=$(default_branch "$repo") || branch=''
    if [ -z "$branch" ] || ! fetch_project "$p"; then
      # Its own job will fail, saying why; the rest are still worth trying.
      echo "::warning::$p: cannot fetch $repo; it stays at ${old:0:12}" >&2
      printf '%-18s %-12s %-12s %-10s %s\n' "$p" "${old:0:12}" "${old:0:12}" '?' 'kept: cannot fetch'
      continue
    fi
    upstream=$(git -C "$src" rev-parse "refs/remotes/origin/$branch")
    olympus=$(git -C "$src" rev-parse -q --verify refs/remotes/origin/olympus || true)
    if [ -z "$olympus" ]; then
      result=none new=$upstream
    elif new=$(rebase_onto "$p" "$upstream" "$olympus"); then
      result=clean
    else
      result=conflict new=$olympus
    fi
    git -C "$src" update-ref refs/olympus/candidate "$new"
    printf 'branch %s\nupstream %s\nolympus %s\nresult %s\n' \
      "$branch" "$upstream" "$olympus" "$result" > "$state/$p"
    case $result in
      none)     note="its $branch (no olympus branch)" ;;
      clean)    note="olympus: $(git -C "$src" rev-list --count "$upstream..$new") commit(s) on its $branch" ;;
      conflict) note="olympus does not rebase onto its $branch (${upstream:0:12}): Copilot will"
                echo "::warning::$p: the olympus branch does not rebase cleanly onto $branch; its Fix job will rebase it" >&2 ;;
    esac
    [ "$new" = "$old" ] && note="unchanged, $note"
  fi
  if [ "$new" != "$old" ] || [ "${result:-}" = conflict ]; then
    changed=1
  fi
  result=''
  sed -E -i "s/^($p):[0-9a-f]+/\1:$new/" "$out"
  printf '%-18s %-12s %-12s %-10s %s\n' "$p" "${old:0:12}" "${new:0:12}" "$branch" "$note"
done

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "changed=$([ "$changed" = 1 ] && echo true || echo false)" >> "$GITHUB_OUTPUT"
fi
msg "candidate hashes written to $out"
