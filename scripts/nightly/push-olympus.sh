#!/usr/bin/env bash
# Usage: scripts/nightly/push-olympus.sh <project>
#
# Move the `olympus` branch of <project> to the commit that the nightly has
# built: the `olympus` commits rebased onto the project's default branch (see
# advance.sh), with the nightly bump and Copilot's repair on top if there
# are any ($OLYMPUS_WORK/nightly/fixed/<project>.hash, from fix.sh, built
# from scratch after it). The commit is pushed from the tree it was made in,
# in $OLYMPUS_WORK/src. Run by the project's own job, as soon as it has
# built, whether or not the other projects build.
#
# A rebase rewrites the branch, so the push is forced, but only with a lease:
# if the `olympus` branch is no longer where the nightly found it, the push
# is refused. A project that has no `olympus` branch gets one only if it now
# has a commit that is not upstream.
#
# For a project whose changes go upstream (pr_project in lib.sh), the branch
# is the head of a pull request to its default branch, which this opens (or
# updates). It is put on the merge queue if every commit in it says
# `Olympus-Change: minimal` and Copilot did not have to resolve conflicts in
# a rebase; otherwise it waits for a review.
#
# What hashes.txt records must stay fetchable after the branch has moved on.
# So every commit that the branch is moved to (other than an upstream one) is
# tagged olympus/<nightly> (e.g. olympus/nightly-2026-10-28, after the F*
# nightly it was built with), and the commit it moves away from, if it is not
# already tagged or upstream, olympus/before-<nightly>.
#
# Once the commit is fetchable from the project's repository, it is noted in
# $OLYMPUS_WORK/nightly/pushed/<project>: hashes.txt is only recorded with
# commits that have been (see publish.sh).
#
# Environment:
#   PUSH                      1 to push; otherwise only say what it would do
#   OLYMPUS_PUSH_TOKEN_<ORG>  the push token of the project's organization
#                             (see push_token_var_of in lib.sh), used only by
#                             the commands that push and open the pull request

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

p=${1:?usage: push-olympus.sh <project>}
repo=$(repo_of "$p")
src=$(src_dir "$p")
pushed=$OLYMPUS_WORK/nightly/pushed
mkdir -p "$pushed"

summary () { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"; return 0; }

new=$(OLYMPUS_HASHES=$OLYMPUS_WORK/candidate-hashes.txt hash_of "$p")
fixed=$OLYMPUS_WORK/nightly/fixed/$p.hash
[ -f "$fixed" ] && new=$(cat "$fixed")

result=$(rebase_info "$p" result)
if [ -z "$result" ]; then
  # advance.sh could not fetch it, and it stays at what hashes.txt has.
  msg "$p: not advanced; nothing to push"
  echo "$new" > "$pushed/$p"
  exit 0
fi
old=$(rebase_info "$p" lease)
upstream=$(rebase_info "$p" upstream)
branch=$(rebase_info "$p" branch)
pr=$(rebase_info "$p" pr)
label=$(fstar_nightly)
[ -n "$label" ] || label=$(date -u +%Y-%m-%d)

# olympus/$1, or olympus/$1.2, .3, ... if that is taken by another commit
# than $2.
tag_for () {
  local name=olympus/$1 n=1 at
  while at=$(git -C "$src" rev-parse -q --verify "refs/tags/$name^{commit}"); do
    [ "$at" = "$2" ] && { echo ''; return; }
    n=$((n + 1)) name=olympus/$1.$n
  done
  echo "$name"
}

refs=()
if [ "$new" != "${old:-$upstream}" ]; then
  refs+=("$new:refs/heads/olympus")
fi
if [ "$new" != "$upstream" ] && [ -z "$(git -C "$src" tag --points-at "$new" -l 'olympus/*')" ]; then
  t=$(tag_for "$label" "$new")
  [ -n "$t" ] && refs+=("$new:refs/tags/$t")
fi
if [ "${#refs[@]}" -gt 0 ] && [ -n "$old" ] && [ "$old" != "$new" ] \
   && ! git -C "$src" merge-base --is-ancestor "$old" "$new" \
   && ! git -C "$src" merge-base --is-ancestor "$old" "$upstream" \
   && [ -z "$(git -C "$src" tag --points-at "$old" -l 'olympus/*')" ]; then
  t=$(tag_for "before-$label" "$old")
  [ -n "$t" ] && refs+=("$old:refs/tags/$t")
fi

# The kinds of change (Olympus-Change) in the commits on top of upstream.
kinds=$(git -C "$src" log --no-merges --format='%(trailers:key=Olympus-Change,valueonly,separator=%x2C)' \
          "$upstream..$new" | sed -e 's/^$/unclassified/' | sort | uniq -c | awk '{ print $2 " (" $1 ")" }' | paste -sd ' ')
small=0
if [ "$new" != "$upstream" ] && [ "$result" != conflict ] \
   && ! git -C "$src" log --no-merges --format='%(trailers:key=Olympus-Change,valueonly,separator=%x2C)' \
          "$upstream..$new" | grep -qvx minimal; then
  small=1
fi

if [ "${PUSH:-0}" != 1 ]; then
  msg "$p: not pushing (a dry run); would push: ${refs[*]:-nothing}"
  pr_project "$p" && [ "$new" != "$upstream" ] \
    && msg "$p: would open or update a pull request to $branch ($kinds; $([ "$small" = 1 ] && echo 'merge queue' || echo 'for review'))"
  exit 0
fi

if [ "${#refs[@]}" -gt 0 ]; then
  msg "$p: pushing to $repo: ${refs[*]}"
  git_push_to "$repo" "$src" --atomic "--force-with-lease=refs/heads/olympus:$old" -- "${refs[@]}" \
    || { echo "::error title=$p::cannot push to the olympus branch of $repo (has it moved since the nightly started?)" >&2; exit 1; }
fi
echo "$new" > "$pushed/$p"

pr_project "$p" || exit 0

GH_TOKEN=$(push_token_of "$repo")
export GH_TOKEN
# The pull request may have been opened since advance.sh looked.
pr=$(gh pr list -R "$repo" --head olympus --state open --json number --jq '.[0].number // empty')

if [ "$new" = "$upstream" ]; then
  if [ -n "$pr" ]; then
    gh pr close "$pr" -R "$repo" --comment "Nothing is left to change: $branch builds with F* $label as it is."
    summary "\`$p\`: closed #$pr, which is not needed any more."
  fi
  exit 0
fi

run_url=${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-FStarLang/OlympusMons}/actions/runs/${GITHUB_RUN_ID:-0}
title="Build with F* $label"
body=$(mktemp)
{
  echo "The [OlympusMons]($run_url) nightly has built this project, from scratch, with F* $label ($(hash_of FStar 2> /dev/null | cut -c1-12)), at the head of this pull request:"
  echo
  git -C "$src" log --no-merges --format='- %h %s (Olympus-Change: %(trailers:key=Olympus-Change,valueonly,separator=%x2C))' "$upstream..$new"
  echo
  if [ "$result" = conflict ]; then
    echo "The previous version of this pull request did not rebase cleanly onto \`$branch\`, and Copilot resolved the conflicts."
    echo
  fi
  if [ "$small" = 1 ]; then
    echo 'Every change is minimal: this is put on the merge queue.'
  else
    echo 'Not every change is minimal: this needs a review before it is merged.'
  fi
  echo
  echo 'The nightly rebases this branch, and adds to it, every night until it is merged; push to it only between nightlies.'
} > "$body"

if [ -z "$pr" ]; then
  url=$(gh pr create -R "$repo" --base "$branch" --head olympus --title "$title" --body-file "$body")
  pr=${url##*/}
  msg "$p: opened $url"
else
  gh pr edit "$pr" -R "$repo" --title "$title" --body-file "$body" > /dev/null
  msg "$p: updated #$pr"
fi
rm -f "$body"

if [ "$small" = 1 ]; then
  if gh pr merge "$pr" -R "$repo" --auto > /dev/null 2>&1 \
     || gh pr merge "$pr" -R "$repo" --auto --merge; then
    summary "\`$p\`: [#$pr](https://github.com/$repo/pull/$pr) is on the merge queue ($kinds)."
  else
    echo "::warning title=$p::could not put #$pr on the merge queue"
    summary "\`$p\`: [#$pr](https://github.com/$repo/pull/$pr) could not be put on the merge queue ($kinds)."
  fi
else
  gh pr merge "$pr" -R "$repo" --disable-auto > /dev/null 2>&1 || true
  summary "\`$p\`: [#$pr](https://github.com/$repo/pull/$pr) needs a review ($kinds)."
fi
