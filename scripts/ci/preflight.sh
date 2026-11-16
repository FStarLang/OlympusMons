#!/usr/bin/env bash
# Usage: scripts/ci/preflight.sh
#
# Check, before any build starts, that the runner can read every repository
# in hashes.txt and that the recorded commits exist. This takes seconds and
# turns the worst failure mode of this CI -- a build that cannot read a
# repository and waits for a password that will never come -- into an
# immediate, named error.
#
# An unreadable project is reported but does not stop the run: the other
# projects are still worth building, and the job of the unreadable one
# fails on its own, in seconds, saying the same thing. Only F* is fatal,
# since nothing can be built without it.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

# ls-remote either answers quickly or cannot answer at all.
# shellcheck disable=SC2034  # read by git_net, in lib.sh
OLYMPUS_NET_TIMEOUT=${OLYMPUS_PREFLIGHT_TIMEOUT:-2m}

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
  # ::error:: even when the run goes on: these projects cannot be built, and
  # that is the run's conclusion however much else succeeds.
  echo "::error::The runner cannot read: ${failed[*]}. Is each repository" \
       "still public (and its name in hashes.txt right), and can the runner" \
       "reach GitHub?"
  case " ${failed[*]} " in
    *" FStar "*) echo "::error::F* cannot be read, so nothing can be built."
                 exit 1 ;;
  esac
  echo "Building the rest; the jobs of the above will fail."
fi
