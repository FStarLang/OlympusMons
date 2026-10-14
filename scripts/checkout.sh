#!/usr/bin/env bash
# Usage: scripts/checkout.sh <project> [<rev>]
#
# Clone (or fetch) <project> into _work/src/<project> and check out the
# commit recorded in hashes.txt (or <rev>), detached. Refuses to touch a
# working tree with local changes to tracked files, unless FORCE=1, which
# discards them. CLEAN=1 also deletes all untracked and ignored files (build
# products included, also in F*'s KaRaMeL submodule), for a build from
# scratch. Submodules are not initialized, except for F*'s own KaRaMeL
# submodule: OlympusMons overrides any F*/KaRaMeL pins made by the
# downstream projects (but see build/everparse.sh).
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
  git_net -C "$d" submodule update -q --init karamel
  # git clean does not descend into submodules.
  if [ "${CLEAN:-0}" = 1 ]; then
    git -C "$d/karamel" clean -q -xffd
  fi
fi
msg "$p: at $(git -C "$d" rev-parse --short=12 HEAD)"
