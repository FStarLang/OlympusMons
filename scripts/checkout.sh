#!/usr/bin/env bash
# Usage: scripts/checkout.sh <project> [<rev>]
#
# Clone (or fetch) <project> into _work/src/<project> and check out the
# commit recorded in hashes.txt (or <rev>), detached. Refuses to touch a
# working tree with local changes to tracked files, unless FORCE=1, which
# discards them. Submodules are not initialized, except
# for F*'s own KaRaMeL submodule: OlympusMons overrides any F*/KaRaMeL pins
# made by the downstream projects.

source "$(dirname "$0")/lib.sh"

p=$1
rev=${2:-$(hash_of "$p")}
d=$(src_dir "$p")
url="https://github.com/$(repo_of "$p").git"

if [ ! -d "$d/.git" ]; then
  msg "$p: cloning $url"
  mkdir -p "$(dirname "$d")"
  git_auth clone -q "$url" "$d"
fi

if [ -n "$(git -C "$d" status --porcelain --untracked-files=no)" ]; then
  if [ "${FORCE:-0}" = 1 ]; then
    msg "$p: discarding local changes"
    git -C "$d" reset -q --hard
  else
    echo "$p: $d has local changes, refusing to check out $rev" \
         "(FORCE=1 discards them)" >&2
    exit 1
  fi
fi

if ! git -C "$d" cat-file -e "$rev^{commit}" 2> /dev/null; then
  git_auth -C "$d" fetch -q origin '+refs/heads/*:refs/remotes/origin/*'
fi
if ! git -C "$d" cat-file -e "$rev^{commit}" 2> /dev/null; then
  git_auth -C "$d" fetch -q origin "$rev"
fi

git -C "$d" checkout -q --detach "$rev"
if [ "$p" = FStar ]; then
  git_auth -C "$d" submodule update -q --init karamel
fi
msg "$p: at $(git -C "$d" rev-parse --short=12 HEAD)"
