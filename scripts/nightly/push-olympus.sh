#!/usr/bin/env bash
# Usage: scripts/nightly/push-olympus.sh <candidate-hashes> <fixed-dir>
#
# Move the `olympus` branch of each project to the commit that the nightly
# built: the `olympus` commits rebased onto the project's default branch (see
# advance.sh), with Copilot's fix on top if one was needed (<fixed-dir>/
# <project>.hash, from fix.sh, built from scratch by the Verify job). The
# commits are pushed from the trees they were made in, in $OLYMPUS_WORK/src.
#
# A rebase rewrites the branch, so the push is forced, but only with a lease:
# if the `olympus` branch is no longer where the nightly found it, the push
# is refused. A project that has no `olympus` branch gets one only if it now
# has a commit that is not upstream (a fix).
#
# What hashes.txt records must stay fetchable after the branch has moved on.
# So every commit that the `olympus` branch is moved to (other than an
# upstream one) is tagged olympus/<date>-<commit>, and so is the commit it
# moves away from, if it is not already tagged or upstream.
#
# All the pushes are tried as dry runs first, so that a branch that has
# moved is found before any of them lands. Each project's branch and tags
# are pushed atomically.
#
# Environment: OLYMPUS_PUSH_TOKEN_<ORG>, one for each organization that has a
# project to push (see push_token_var_of in lib.sh), used only by the git
# commands that push.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

candidate=${1:?usage: push-olympus.sh <candidate-hashes> <fixed-dir>}
fixed=${2:?}
today=$(date -u +%Y-%m-%d)

todo=()
declare -A refs_of lease_of
for p in "${PROJECTS[@]}"; do
  [ "$p" = FStar ] && continue
  # A project that advance.sh could not fetch stays where it was.
  [ -n "$(rebase_info "$p" result)" ] || continue
  src=$(src_dir "$p")
  new=$(OLYMPUS_HASHES=$candidate hash_of "$p")
  [ -f "$fixed/$p.hash" ] && new=$(cat "$fixed/$p.hash")
  old=$(rebase_info "$p" olympus)
  upstream=$(rebase_info "$p" upstream)
  [ "$new" = "$old" ] && continue
  [ -z "$old" ] && [ "$new" = "$upstream" ] && continue

  refs=("$new:refs/heads/olympus")
  [ "$new" != "$upstream" ] && refs+=("$new:refs/tags/olympus/$today-${new:0:12}")
  if [ -n "$old" ] && ! git -C "$src" merge-base --is-ancestor "$old" "$new" \
     && ! git -C "$src" merge-base --is-ancestor "$old" "$upstream" \
     && [ -z "$(git -C "$src" tag --points-at "$old" -l 'olympus/*')" ]; then
    refs+=("$old:refs/tags/olympus/$today-${old:0:12}")
  fi
  todo+=("$p")
  refs_of[$p]="${refs[*]}"
  lease_of[$p]="--force-with-lease=refs/heads/olympus:$old"
done

push () {
  local p=$1 r
  shift
  read -r -a r <<< "${refs_of[$p]}"
  git_push_to "$(repo_of "$p")" "$(src_dir "$p")" --atomic "${lease_of[$p]}" "$@" -- "${r[@]}"
}

for p in "${todo[@]}"; do
  push "$p" --dry-run \
    || { echo "::error::$p: cannot push to the olympus branch of $(repo_of "$p") (has it moved since the nightly started?). Nothing was pushed." >&2; exit 1; }
done
for p in "${todo[@]}"; do
  msg "$p: pushing to $(repo_of "$p"): ${refs_of[$p]}"
  push "$p"
done
msg "moved ${#todo[@]} olympus branch(es)"
