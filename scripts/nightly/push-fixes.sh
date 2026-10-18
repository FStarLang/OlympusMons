#!/usr/bin/env bash
# Usage: scripts/nightly/push-fixes.sh <candidate-hashes> <fixed-dir>
#
# Push the commits that fix.sh made (and the Verify job built from scratch)
# to the `olympus` branch of each project, from the trees they were made in,
# in $OLYMPUS_WORK/src. Never forced. All the pushes are tried as dry runs
# first, so that a branch that has moved is found before any of them lands.
#
# Environment: OLYMPUS_PUSH_TOKEN_<ORG>, one for each organization that has a
# project to push (see push_token_var_of in lib.sh), used only by the git
# commands that push.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

candidate=${1:?usage: push-fixes.sh <candidate-hashes> <fixed-dir>}
fixed=${2:?}

push () {
  local p=$1 rev=$2; shift 2
  git_push_to "$(repo_of "$p")" "$(src_dir "$p")" "$rev:refs/heads/olympus" "$@"
}

todo=()
for f in "$fixed"/*.hash; do
  [ -e "$f" ] || continue
  p=$(basename "$f" .hash)
  rev=$(cat "$f")
  # No change was needed: nothing to push.
  [ "$rev" = "$(OLYMPUS_HASHES=$candidate hash_of "$p")" ] && continue
  todo+=("$p:$rev")
done

for x in "${todo[@]}"; do
  push "${x%%:*}" "${x#*:}" --dry-run \
    || { echo "::error::${x%%:*}: cannot push ${x#*:} to the olympus branch of $(repo_of "${x%%:*}") (has it moved?). Nothing was pushed." >&2; exit 1; }
done
for x in "${todo[@]}"; do
  msg "${x%%:*}: pushing ${x#*:} to $(repo_of "${x%%:*}") olympus"
  push "${x%%:*}" "${x#*:}"
done
msg "pushed ${#todo[@]} fix(es)"
