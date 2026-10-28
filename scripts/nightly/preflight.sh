#!/usr/bin/env bash
# Usage: scripts/nightly/preflight.sh
#
# Fail fast, in the first job rather than the last, if the nightly could not
# do what it is for: recording its result needs to push to OlympusMons, and
# fixing needs Copilot and push access to every project.
#
# Environment: PUBLISH and FIX (true/false), COPILOT_GITHUB_TOKEN, and the
# push token of each organization, OLYMPUS_PUSH_TOKEN_FSTARLANG and
# OLYMPUS_PUSH_TOKEN_PROJECT_EVEREST (see push_token_var_of in lib.sh). Sets `fix` (true/false) in $GITHUB_OUTPUT.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

problems=0
fix=true
problem () { echo "::error::$*"; problems=1; }

if [ -z "${COPILOT_GITHUB_TOKEN:-}" ]; then
  echo "::warning::the secret COPILOT_GITHUB_TOKEN is not set: failures will not be fixed"
  fix=false
fi
[ "${FIX:-true}" = true ] || fix=false

# What the push tokens must be able to write to: this repository, to publish,
# and every project, to publish a fix to its olympus branch.
publish_repo=${GITHUB_REPOSITORY:-FStarLang/OlympusMons}
project_repos=()
for p in "${PROJECTS[@]}"; do
  [ "$p" = FStar ] || project_repos+=("$(repo_of "$p")")
done

# Is there a token for the repository's organization, and can it write there?
# A dry run of a push authenticates and checks permissions, and changes
# nothing. Prints nothing and returns 1 if it cannot.
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
git -C "$probe" init -q
git -C "$probe" -c user.name=probe -c user.email=probe@example.com commit -q --allow-empty -m probe
can_push () {
  local repo=$1 var
  var=$(push_token_var_of "$repo") || { echo "  $repo: no secret for its organization"; return 1; }
  if ! git_push_to "$repo" "$probe" --dry-run -- HEAD:refs/heads/olympus-nightly-probe > /dev/null 2>&1; then
    echo "  $repo: cannot push (is the secret $var set, and allowed to write there?)"
    return 1
  fi
  echo "  can push to $repo"
}

if [ "${PUBLISH:-true}" = true ]; then
  can_push "$publish_repo" || problem "cannot publish: the secret for $publish_repo is missing or cannot push to it (publish=false skips this)"
fi
if [ "$fix" = true ]; then
  bad=()
  for r in "${project_repos[@]}"; do
    can_push "$r" || bad+=("$r")
  done
  if [ "${#bad[@]}" -gt 0 ]; then
    # Publishing a result that was fixed needs every project's token, and
    # fixing without publishing is pointless.
    if [ "${PUBLISH:-true}" = true ]; then
      problem "a fix could not be pushed to: ${bad[*]}"
    else
      echo "::warning::cannot push to: ${bad[*]}; failures will not be fixed"
      fix=false
    fi
  fi
fi

[ -n "${GITHUB_OUTPUT:-}" ] && echo "fix=$fix" >> "$GITHUB_OUTPUT"
exit "$problems"
