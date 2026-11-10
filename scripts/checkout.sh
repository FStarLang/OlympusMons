#!/usr/bin/env bash
# Usage: scripts/checkout.sh <project> [<rev>]
#
# Clone (or fetch) <project> into _work/src/<project> and check out the
# commit recorded in hashes.txt (or <rev>), detached. CLEAN=1 restores the
# tree to exactly that commit, discarding everything an earlier build left
# behind: all untracked and ignored files (build products included, also in
# F*'s submodules) and any change to a tracked file. Without CLEAN, a tree
# with modified tracked files is left alone and the checkout fails, unless
# FORCE=1. Submodules are not initialized, except for F*'s own (KaRaMeL,
# and mimalloc for Cherry): OlympusMons overrides any F*/KaRaMeL pins made
# by the downstream projects (but see build/everparse.sh).
#
# Every operation that talks to GitHub is bounded by $OLYMPUS_NET_TIMEOUT,
# and git never prompts (see lib.sh), so a repository the runner cannot read
# fails here, quickly and by name, instead of hanging the build.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

p=$1
rev=${2:-$(hash_of "$p")}
d=$(src_dir "$p")
url="https://github.com/$(repo_of "$p").git"

if [ ! -d "$d/.git" ]; then
  msg "$p: cloning $url"
  mkdir -p "$(dirname "$d")"
  # A clone that fails or is killed leaves a partial tree behind, which
  # would make every later run take this branch and fail the same way.
  if ! git_net clone -q "$url" "$d"; then
    rm -rf "$d"
    echo "$p: cannot clone $url (is \$GH_TOKEN set, and does it grant" \
         "read access to $(repo_of "$p")?)" >&2
    exit 1
  fi
fi

# A build may modify the tracked files of its own tree: several of these
# projects regenerate files that are committed -- hacl-pulse's extracted
# dist/, pulse-verified-gc's generational/snapshot/ -- and check the result
# against what is recorded. A tree that has been built in is therefore
# dirty, and the next build must put it back. CLEAN=1 (a build from
# scratch, which deletes every untracked and ignored file below) discards
# those changes; without it, they may be someone's work in progress.
if [ -n "$(git -C "$d" status --porcelain --untracked-files=no)" ]; then
  if [ "${CLEAN:-0}" = 1 ] || [ "${FORCE:-0}" = 1 ]; then
    msg "$p: discarding changes to tracked files"
    git -C "$d" reset -q --hard
  else
    echo "$p: $d has local changes, refusing to check out $rev" \
         "(CLEAN=1 or FORCE=1 discards them)" >&2
    exit 1
  fi
fi

if ! git -C "$d" cat-file -e "$rev^{commit}" 2> /dev/null; then
  git_net -C "$d" fetch -q origin '+refs/heads/*:refs/remotes/origin/*'
fi
if ! git -C "$d" cat-file -e "$rev^{commit}" 2> /dev/null; then
  git_net -C "$d" fetch -q origin "$rev"
fi

git -C "$d" checkout -q --detach "$rev"
if [ "${CLEAN:-0}" = 1 ]; then
  msg "$p: deleting untracked and ignored files"
  git -C "$d" clean -q -xffd
fi
if [ "$p" = FStar ]; then
  # The submodules (KaRaMeL has a build in it too) are checked out, which
  # `submodule update` will not do over changes to their tracked files, and
  # git clean does not descend into them.
  if [ "${CLEAN:-0}" = 1 ]; then
    git -C "$d" submodule foreach -q 'git reset -q --hard'
  fi
  git_net -C "$d" submodule update -q --init
  if [ "${CLEAN:-0}" = 1 ]; then
    git -C "$d" submodule foreach -q 'git clean -q -xffd'
  fi
fi
msg "$p: at $(git -C "$d" rev-parse --short=12 HEAD)"
