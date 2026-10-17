#!/usr/bin/env bash
# Usage: scripts/ci/add-runners.sh [<count>]
#        scripts/ci/add-runners.sh --list
#        scripts/ci/add-runners.sh --remove
#
# Register <count> self-hosted runners (default 8) on this machine, as
# services, all with the label `olympus`.
#
# The Build workflow is a graph of jobs that are meant to run at the same
# time, but a runner only ever runs one job at a time: with a single runner
# registered, the per-project jobs queue up and the build takes as long as
# all of them put together. One runner per concurrent job restores the
# parallelism of the old single-job build, while keeping a job -- a line in
# the run's graph, a log, a time limit -- per project.
#
# The runners all run as the current user and share one build tree
# (~/olympus-work), so the concurrent builds reuse one F* package and one
# set of clones; what they do not share is cores, so see OLYMPUS_JOBS in
# README.md if the machine ends up oversubscribed.
#
# Run this on the build machine, as the user that the runners run as, with
# sudo available and `gh` logged in as someone who administers the
# repository (or with $GH_TOKEN set to such a token).

set -euo pipefail

REPO=${OLYMPUS_REPO:-FStarLang/OlympusMons}
BASE=${OLYMPUS_RUNNER_BASE:-$HOME}
LABELS=${OLYMPUS_RUNNER_LABELS:-olympus}
PREFIX=${OLYMPUS_RUNNER_PREFIX:-olympus}

msg () { printf '[olympus] %s\n' "$*" >&2; }
die () { printf '[olympus] error: %s\n' "$*" >&2; exit 1; }

runner_dirs () {
  # Only the ones this script made; an existing hand-made runner is left be.
  find "$BASE" -maxdepth 1 -name "actions-runner-$PREFIX-*" -type d 2> /dev/null | sort -V
}

list () {
  printf '%-28s %-10s %s\n' DIRECTORY CONFIGURED SERVICE
  local d name svc state
  while read -r d; do
    [ -n "$d" ] || continue
    name=$(basename "$d")
    if [ -f "$d/.runner" ]; then
      svc=$(sed -n 's/^SVC_NAME=//p' "$d/.service" 2> /dev/null | tr -d "'\"")
      state=$(systemctl is-active "${svc:-nonexistent}" 2> /dev/null || true)
      printf '%-28s %-10s %s\n' "$name" yes "${svc:+$svc: }${state:-not installed}"
    else
      printf '%-28s %-10s %s\n' "$name" no -
    fi
  done <<< "$(runner_dirs)"
  echo
  msg "runners known to $REPO:"
  gh api "repos/$REPO/actions/runners" \
    --jq '.runners[] | "  \(.name)  \(.status)  busy=\(.busy)  [\([.labels[].name] | join(","))]"' \
    2> /dev/null || msg "  (could not ask GitHub)"
}

remove () {
  local d name
  while read -r d; do
    [ -n "$d" ] || continue
    name=$(basename "$d")
    msg "$name: stopping and unregistering"
    ( cd "$d"
      sudo ./svc.sh stop > /dev/null 2>&1 || true
      sudo ./svc.sh uninstall > /dev/null 2>&1 || true
      if [ -f .runner ]; then
        ./config.sh remove --token "$(registration_token remove)" || true
      fi )
    rm -rf "$d"
  done <<< "$(runner_dirs)"
  msg "done; the runners this script created are gone"
}

registration_token () {
  local kind=${1:-registration}
  gh api -X POST "repos/$REPO/actions/runners/${kind}-token" --jq .token \
    || die "could not get a $kind token for $REPO; is gh logged in as an administrator of it?"
}

# The runner package, downloaded once and unpacked into each runner's
# directory.
fetch_package () {
  local cache=$BASE/.olympus-runner-cache ver arch tgz
  mkdir -p "$cache"
  ver=$(gh api repos/actions/runner/releases/latest --jq .tag_name) \
    || die 'could not find the latest runner release'
  ver=${ver#v}
  arch=x64
  [ "$(uname -m)" = aarch64 ] && arch=arm64
  tgz=$cache/actions-runner-linux-$arch-$ver.tar.gz
  if [ ! -s "$tgz" ]; then
    msg "downloading the v$ver runner"
    curl -fsSL -o "$tgz.part" \
      "https://github.com/actions/runner/releases/download/v$ver/actions-runner-linux-$arch-$ver.tar.gz" \
      || die "could not download the v$ver runner"
    mv "$tgz.part" "$tgz"
  fi
  echo "$tgz"
}

add () {
  local count=$1 tgz i d name
  command -v gh > /dev/null || die 'gh is not installed'
  gh auth status > /dev/null 2>&1 || [ -n "${GH_TOKEN:-}" ] \
    || die "gh is not logged in and \$GH_TOKEN is unset"
  sudo -n true 2> /dev/null || msg 'sudo may ask for your password (svc.sh needs root)'

  tgz=$(fetch_package)
  for i in $(seq 1 "$count"); do
    name=$(printf '%s-%s-%02d' "$(hostname -s)" "$PREFIX" "$i")
    d=$BASE/actions-runner-$PREFIX-$(printf '%02d' "$i")

    if [ -f "$d/.runner" ]; then
      msg "$name: already configured; making sure its service is running"
      ( cd "$d" && sudo ./svc.sh start > /dev/null 2>&1 ) || true
      continue
    fi

    msg "$name: unpacking into $d"
    mkdir -p "$d"
    tar -C "$d" -xzf "$tgz"

    msg "$name: registering with $REPO, labels: $LABELS"
    ( cd "$d"
      ./config.sh --unattended --replace \
        --url "https://github.com/$REPO" \
        --token "$(registration_token registration)" \
        --name "$name" --labels "$LABELS" --work _work
      sudo ./svc.sh install "$(id -un)"
      sudo ./svc.sh start )
  done

  echo
  list
}

case "${1:-8}" in
  --list)   list ;;
  --remove) remove ;;
  --help|-h) sed -n '2,/^$/p' "$0" ;;
  ''|*[!0-9]*) die "expected a count, --list or --remove, not '${1:-}'" ;;
  *)        add "$1" ;;
esac
