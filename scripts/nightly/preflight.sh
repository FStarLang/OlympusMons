#!/usr/bin/env bash
# Usage: scripts/nightly/preflight.sh
#
# Fail fast, in the first job rather than the last, if the nightly could not
# do what it is for: record its result needs to push to OlympusMons, and
# fixing needs Copilot and push access to every project.
#
# Environment: PUBLISH (true/false), FIX_ATTEMPTS, COPILOT_GITHUB_TOKEN,
# OLYMPUS_PUSH_TOKEN. Sets `fix` (true/false) in $GITHUB_OUTPUT.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

problems=0
fix=true
problem () { echo "::error::$*"; problems=1; }

if [ -z "${OLYMPUS_PUSH_TOKEN:-}" ]; then
  if [ "${PUBLISH:-true}" = true ]; then
    problem "the secret OLYMPUS_PUSH_TOKEN is not set: the nightly cannot push (publish=false would skip that)"
  else
    echo "::warning::OLYMPUS_PUSH_TOKEN is not set: fixes cannot be pushed, so there will be none"
    fix=false
  fi
fi
if [ -z "${COPILOT_GITHUB_TOKEN:-}" ]; then
  echo "::warning::the secret COPILOT_GITHUB_TOKEN is not set: failures will not be fixed"
  fix=false
fi
[ "${FIX_ATTEMPTS:-3}" = 0 ] && fix=false

# Can the token write where it must? A dry run of a push authenticates and
# checks permissions, and changes nothing.
can_push () {
  local dir=$1 repo=$2
  # shellcheck disable=SC2016
  env OLYMPUS_PUSH_TOKEN="$OLYMPUS_PUSH_TOKEN" GIT_TERMINAL_PROMPT=0 git -C "$dir" \
      -c credential.helper= \
      -c 'credential.helper=!f() { echo username=x-access-token; echo "password=$OLYMPUS_PUSH_TOKEN"; }; f' \
      push --dry-run "https://github.com/$repo.git" HEAD:refs/heads/olympus-nightly-probe \
      > /dev/null 2>&1
}

if [ -n "${OLYMPUS_PUSH_TOKEN:-}" ]; then
  repos=("${GITHUB_REPOSITORY:-FStarLang/OlympusMons}")
  [ "${FIX_ATTEMPTS:-3}" != 0 ] && for p in "${PROJECTS[@]}"; do
    [ "$p" = FStar ] || repos+=("$(repo_of "$p")")
  done
  probe=$(mktemp -d)
  git -C "$probe" init -q
  git -C "$probe" -c user.name=probe -c user.email=probe@example.com commit -q --allow-empty -m probe
  for r in "${repos[@]}"; do
    if can_push "$probe" "$r"; then
      printf '  can push to %s\n' "$r"
    else
      problem "OLYMPUS_PUSH_TOKEN cannot push to $r"
    fi
  done
  rm -rf "$probe"
fi

[ -n "${GITHUB_OUTPUT:-}" ] && echo "fix=$fix" >> "$GITHUB_OUTPUT"
exit "$problems"
