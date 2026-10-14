#!/usr/bin/env bash
# Usage: scripts/ci/preflight.sh
#
# Check, before any build starts, that the runner can read every repository
# in hashes.txt and that the recorded commits exist. This takes seconds and
# turns the worst failure mode of this CI -- a build that cannot read a
# private repository and waits for a password that will never come -- into
# an immediate, named error.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

# ls-remote either answers quickly or cannot answer at all.
# shellcheck disable=SC2034  # read by git_net, in lib.sh
OLYMPUS_NET_TIMEOUT=${OLYMPUS_PREFLIGHT_TIMEOUT:-2m}

if command -v gh > /dev/null; then
  if gh auth status > /dev/null 2>&1; then
    msg "authenticated to GitHub as $(gh api user --jq .login 2> /dev/null || echo '(unknown)')"
  else
    msg "WARNING: gh is not authenticated and \$GH_TOKEN is $( [ -n "${GH_TOKEN:-}" ] && echo set || echo unset ); private repositories will fail below"
  fi
fi

printf '%-18s %-28s %-13s %s\n' PROJECT REPOSITORY COMMIT ACCESS
failed=()
for p in "${PROJECTS[@]}"; do
  repo=$(repo_of "$p")
  rev=$(hash_of "$p")
  if out=$(git_net ls-remote "https://github.com/$repo.git" 2>&1); then
    if grep -q "^$rev" <<< "$out"; then
      access='ok'
    else
      # The commit is not at the tip of a branch, which is normal for a pin;
      # we can only confirm it once the repository is cloned.
      access='ok (commit not a ref tip)'
    fi
  else
    access='UNREADABLE'
    failed+=("$p ($repo)")
  fi
  printf '%-18s %-28s %-13s %s\n' "$p" "$repo" "${rev:0:12}" "$access"
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo
  echo "::error::The runner cannot read: ${failed[*]}. Give it read access" \
       "(the OLYMPUS_GH_TOKEN repository secret, or \`gh auth login\` as the" \
       "runner's user) -- see \"Continuous integration\" in README.md."
  exit 1
fi
