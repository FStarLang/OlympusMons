#!/usr/bin/env bash
# Usage: scripts/nightly/push-fixes.sh <candidate-hashes> <fixed-dir>
#
# Push the commits that fix.sh made (and the Verify job built from scratch)
# to the `olympus` branch of each project, from the trees they were made in,
# in $OLYMPUS_WORK/src. Never forced. All the pushes are tried as dry runs
# first, so that a branch that has moved is found before any of them lands.
#
# Environment: OLYMPUS_PUSH_TOKEN, used only by the git commands that push.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

candidate=${1:?usage: push-fixes.sh <candidate-hashes> <fixed-dir>}
fixed=${2:?}
: "${OLYMPUS_PUSH_TOKEN:?OLYMPUS_PUSH_TOKEN is not set}"
export GIT_TERMINAL_PROMPT=0

push () {
  local p=$1 rev=$2; shift 2
  # shellcheck disable=SC2016
  git -C "$(src_dir "$p")" \
      -c credential.helper= \
      -c 'credential.helper=!f() { echo username=x-access-token; echo "password=$OLYMPUS_PUSH_TOKEN"; }; f' \
      push "$@" "https://github.com/$(repo_of "$p").git" "$rev:refs/heads/olympus"
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
