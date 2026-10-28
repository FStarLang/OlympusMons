# Common definitions for the OlympusMons scripts. Source this file, do not
# execute it.

set -euo pipefail

OLYMPUS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OLYMPUS_WORK=${OLYMPUS_WORK:-$OLYMPUS_ROOT/_work}
OLYMPUS_HASHES=${OLYMPUS_HASHES:-$OLYMPUS_ROOT/hashes.txt}
OLYMPUS_OPAM_SWITCH=${OLYMPUS_OPAM_SWITCH:-olympus}
JOBS=${JOBS:-$(nproc)}

# Nothing in a build may wait for a human: a build that needs input is a
# build that hangs until its timeout (as a clone of the private hacl-pulse
# once did, for eleven hours). Make git and gh fail instead of prompting.
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=
export SSH_ASKPASS=
export GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -oBatchMode=yes"}
export GCM_INTERACTIVE=never
export DEBIAN_FRONTEND=noninteractive
export OPAMYES=1

# An unset repository secret reaches the build as an empty GH_TOKEN, which
# gh reports as a bad credential rather than falling back to the runner's
# own `gh auth login`. Treat empty as absent.
[ -z "${GH_TOKEN:-}" ] && unset GH_TOKEN
[ -z "${GITHUB_TOKEN:-}" ] && unset GITHUB_TOKEN

# How long a single git network operation may take, how often a running
# build reports that it is still alive, and (see timeout_of) how long a
# build may run. Durations are as timeout(1) accepts them.
OLYMPUS_NET_TIMEOUT=${OLYMPUS_NET_TIMEOUT:-20m}
OLYMPUS_HEARTBEAT=${OLYMPUS_HEARTBEAT:-120}

# The F* package (bin/fstar.exe, bin/krml, lib/...) built from the recorded
# FStar commit. All downstream projects are built against it.
FSTAR_PKG=$OLYMPUS_WORK/fstar
# A snapshot of the parts of the F* source tree (at the same commit) that
# some projects need: Pulse's makefile library and examples. Shared by the
# jobs that run at the same time, and so read-only to them, with one
# exception: EverParse builds the DICE example in place. The FStar target
# recreates it, so nothing in it survives a build from scratch.
FSTAR_SRC=$OLYMPUS_WORK/fstar-src
# The Z3 that the recorded F* uses by default, as z3 and z3-<version>, and
# stubs that shadow any other Z3 in PATH (see install-z3.sh). This is the
# only Z3 that F* and the projects can use.
Z3_BIN=$OLYMPUS_WORK/z3

PROJECTS=(FStar everparse pal kuiper pulse-verified-gc AlgoStar hacl-pulse)
# Every build target, in the order the status table lists them. FStar-ci is
# F*'s own CI, run in the tree that the FStar target built.
# shellcheck disable=SC2034  # used by the scripts that source this file
TARGETS=(FStar FStar-ci "${PROJECTS[@]:1}")

repo_of () {
  case "$1" in
    FStar)             echo FStarLang/FStar ;;
    everparse)         echo project-everest/everparse ;;
    pal)               echo FStarLang/pal ;;
    kuiper)            echo FStarLang/kuiper ;;
    pulse-verified-gc) echo FStarLang/pulse-verified-gc ;;
    AlgoStar)          echo FStarLang/AlgoStar ;;
    hacl-pulse)        echo FStarLang/hacl-pulse ;;
    # Not a project: the KaRaMeL that EverParse pins (see build/everparse.sh).
    everparse-karamel) echo FStarLang/karamel ;;
    *) echo "unknown project: $1" >&2; return 1 ;;
  esac
}

# The commit recorded for project $1 in hashes.txt.
hash_of () {
  local h
  h=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$OLYMPUS_HASHES" \
      | awk -F: -v p="$1" '$1 == p { print $2 }')
  if [ -z "$h" ]; then
    echo "no hash recorded for $1 in $OLYMPUS_HASHES" >&2
    return 1
  fi
  echo "$h"
}

# The secret that can push to repository $1 (owner/name): a token has one
# resource owner, so there is one per organization (see "The nightly" in
# README.md). Prints the name of the variable that holds it.
push_token_var_of () {
  case "${1%%/*}" in
    FStarLang)        echo OLYMPUS_PUSH_TOKEN_FSTARLANG ;;
    project-everest)  echo OLYMPUS_PUSH_TOKEN_PROJECT_EVEREST ;;
    *) echo "no push token is configured for the organization of $1" >&2; return 1 ;;
  esac
}

# git push, in directory $2, to repository $1 (owner/name), as the token of
# its organization, which the credential helper hands to git and which is
# otherwise not visible to it. The rest of the arguments are options of `git
# push`, then `--`, then the refspecs:
#
#   git_push_to <repo> <dir> [<option>...] -- <refspec>...
#
# Fails if there is no such token.
git_push_to () {
  local repo=$1 dir=$2 var tok opts=()
  shift 2
  while [ "$#" -gt 0 ] && [ "$1" != -- ]; do opts+=("$1"); shift; done
  [ "${1:-}" = -- ] && shift
  var=$(push_token_var_of "$repo")
  case $var in
    OLYMPUS_PUSH_TOKEN_FSTARLANG) tok=${OLYMPUS_PUSH_TOKEN_FSTARLANG:-} ;;
    OLYMPUS_PUSH_TOKEN_PROJECT_EVEREST) tok=${OLYMPUS_PUSH_TOKEN_PROJECT_EVEREST:-} ;;
  esac
  if [ -z "$tok" ]; then
    echo "$var is not set: cannot push to $repo" >&2
    return 1
  fi
  # shellcheck disable=SC2016  # expanded by the helper, from the environment
  GIT_TERMINAL_PROMPT=0 OLYMPUS_PUSH_TOKEN_NOW=$tok git -C "$dir" \
      -c credential.helper= \
      -c 'credential.helper=!f() { echo username=x-access-token; echo "password=$OLYMPUS_PUSH_TOKEN_NOW"; }; f' \
      push "${opts[@]}" "https://github.com/$repo.git" "$@"
}

src_dir () { echo "$OLYMPUS_WORK/src/$1"; }

# Who the nightly's commits (its rebases and its fixes) are by.
# shellcheck disable=SC2034  # used by the scripts that source this file
NIGHTLY_GIT_ID=(-c user.name='OlympusMons nightly'
                -c user.email='olympusmons-nightly@users.noreply.github.com')

# What the nightly found when it rebased project $1's `olympus` branch onto
# the tip of its default branch (see nightly/advance.sh): the value of key $2,
# or nothing if there is none (or no nightly ran in this tree).
#
#   branch    the default branch, e.g. main
#   upstream  its tip
#   olympus   the tip of the `olympus` branch (empty if there is none)
#   result    none (no `olympus` branch), clean (rebased, or nothing to
#             rebase), or conflict (the rebase stopped with conflicts, and
#             the candidate is the unrebased `olympus` tip: fix.sh rebases)
rebase_info () {
  local f=$OLYMPUS_WORK/nightly/rebase/$1
  [ -f "$f" ] || return 0
  awk -v k="$2" '$1 == k { print $2 }' "$f"
}

# How long target $1 may run before run.sh kills it and reports what it was
# doing. These are deliberately generous -- several times the longest time
# the target has been observed to take -- because their purpose is not to
# enforce a budget but to turn "the job ran out of time with nothing in the
# log" into "this target hung, here is the command it hung in". $OLYMPUS_TIMEOUT
# overrides them.
timeout_of () {
  if [ -n "${OLYMPUS_TIMEOUT:-}" ]; then echo "$OLYMPUS_TIMEOUT"; return; fi
  case "$1" in
    FStar)             echo 60m ;;
    FStar-ci)          echo 120m ;;
    everparse)         echo 180m ;;
    pal)               echo 90m ;;
    kuiper)            echo 150m ;;
    pulse-verified-gc) echo 120m ;;
    AlgoStar)          echo 90m ;;
    # The longest of them: 1h15m-1h21m in the runs so far (it extracts
    # with Custard, compiles the result and runs the C tests).
    hacl-pulse)        echo 240m ;;
    *)                 echo 240m ;;
  esac
}

# git, authenticating HTTPS through the GitHub CLI when it is available
# (some of the repositories are private).
if command -v gh > /dev/null; then
  GIT_AUTH=(git -c credential.helper=
            -c 'credential.helper=!gh auth git-credential')
else
  GIT_AUTH=(git)
fi

git_auth () { "${GIT_AUTH[@]}" "$@"; }

# git_auth for an operation that talks to GitHub, bounded by
# $OLYMPUS_NET_TIMEOUT. Without this, a repository the runner cannot read (a
# missing or expired token for a private one) blocks the build until the
# job's own timeout, with nothing in the log to say which repository it was.
git_net () {
  local rc=0
  timeout -k 30s "$OLYMPUS_NET_TIMEOUT" "${GIT_AUTH[@]}" "$@" || rc=$?
  if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then
    echo "git $1 took longer than $OLYMPUS_NET_TIMEOUT and was killed;" \
         "the runner is probably unable to authenticate to GitHub" >&2
  fi
  return "$rc"
}

# OCaml (the dedicated opam switch) and Z3. This is all F* itself needs.
base_env () {
  if [ -n "$OLYMPUS_OPAM_SWITCH" ]; then
    eval "$(opam env --switch="$OLYMPUS_OPAM_SWITCH" --set-switch)"
  fi
  if [ ! -x "$Z3_BIN/z3" ]; then
    echo "no Z3 in $Z3_BIN; run scripts/install-z3.sh (or build FStar)" >&2
    return 1
  fi
  export PATH="$Z3_BIN:$PATH"
  # Its version (e.g. 5.3.0), for the projects that pin a Z3 version.
  OLYMPUS_Z3_VERSION=$(z3 --version | awk '{ print $3 }')
  export OLYMPUS_Z3_VERSION
  # Builds must succeed without proof recovery or other leniency.
  unset OTHERFLAGS FSTAR_EXE FSTAR_HOME FSTAR_ROOT KRML_EXE KRML_HOME PULSE_ROOT
  # A GitHub token in the environment (e.g. in CI) is only for checkout.sh.
  unset GH_TOKEN GITHUB_TOKEN
}

# Environment for building a downstream project against the OlympusMons F*.
# This overrides whatever F*/KaRaMeL/Pulse the projects would otherwise pick
# up (submodules, nightlies, pinned hashes, ...).
olympus_env () {
  base_env
  if [ ! -x "$FSTAR_PKG/bin/fstar.exe" ]; then
    echo "no F* package at $FSTAR_PKG; build FStar first" >&2
    return 1
  fi
  export PATH="$FSTAR_PKG/bin:$PATH"
  export FSTAR_EXE="$FSTAR_PKG/bin/fstar.exe"
  export KRML_EXE="$FSTAR_PKG/bin/krml"
  export FSTAR_HOME="$FSTAR_PKG"
  export FSTAR_ROOT="$FSTAR_PKG"
  # A KaRaMeL source tree layout within the package (see build/FStar.sh).
  export KRML_HOME="$FSTAR_PKG/karamel"
  export PULSE_ROOT="$FSTAR_SRC/pulse"
}

# make, in parallel. Under a parallel OlympusMons make, use its jobserver
# rather than starting another $JOBS-wide build.
pmake () {
  if [[ " ${MAKEFLAGS:-} " == *jobserver* ]]; then
    make "$@"
  else
    make -j"$JOBS" "$@"
  fi
}

msg () { printf '[olympus] %s\n' "$*" >&2; }

# A duration as timeout(1) accepts it (120, 90s, 30m, 2h), in seconds.
timeout_secs () {
  local d=$1 n=${1%[smhd]} u=${1: -1}
  case $u in
    s) echo "$n" ;;
    m) echo "$((n * 60))" ;;
    h) echo "$((n * 3600))" ;;
    d) echo "$((n * 86400))" ;;
    *) echo "$d" ;;
  esac
}

# A number of seconds as 1h02m03s or 9m25s.
duration () {
  local s=$1
  if [ "$s" -ge 3600 ]; then
    printf '%dh%02dm%02ds' "$((s / 3600))" "$((s % 3600 / 60))" "$((s % 60))"
  else
    printf '%dm%02ds' "$((s / 60))" "$((s % 60))"
  fi
}

# How long since the epoch second $1.
elapsed () { duration "$(( $(date +%s) - $1 ))"; }

# Fold the output of a command into a collapsible group in the GitHub
# Actions log (and just print a header elsewhere).
group () {
  local title=$1; shift
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    printf '::group::%s\n' "$title"
  else
    printf '===== %s =====\n' "$title"
  fi
  "$@" || true
  [ -n "${GITHUB_ACTIONS:-}" ] && printf '::endgroup::\n'
  return 0
}

# The process tree rooted at $1, one line per process, most recent command
# first. Built from a flat `ps` listing rather than `ps --forest`/`pstree`,
# neither of which can be relied on to select exactly our descendants.
proc_tree () {
  ps -eo pid=,ppid=,etime=,pcpu=,rss=,stat=,args= 2> /dev/null | awk -v root="$1" '
    {
      pid = $1; ppid = $2
      args = ""
      for (i = 7; i <= NF; i++) args = args (i > 7 ? " " : "") $i
      info[pid] = sprintf("%9s %5s%% %8sk %-4s %s", $3, $4, $5, $6, substr(args, 1, 160))
      kids[ppid, ++n[ppid]] = pid
    }
    END {
      if (!(root in info)) { print "  (process " root " is already gone)"; exit }
      printf "%-8s %9s %6s %9s %-4s %s\n", "PID", "ELAPSED", "CPU", "RSS", "STAT", "COMMAND"
      walk(root, "")
    }
    function walk(p, indent,   i) {
      if (p in info) printf "%-8s %s%s\n", p, indent, info[p]
      for (i = 1; i <= n[p]; i++) walk(kids[p, i], indent "  ")
    }'
}

# What the machine is doing: the process tree under $1 (a pid), the load and
# the free disk. Printed when a build is killed for running too long, so
# that the log says which command hung rather than only that something did.
diagnose () {
  local pid=${1:-$$}
  echo
  echo "===== diagnostics at $(date -Is) ====="
  echo "--- uptime ---"; uptime
  echo "--- memory ---"; free -h 2> /dev/null || true
  echo "--- disk ---"; df -h "$OLYMPUS_WORK" 2> /dev/null || df -h
  echo "--- the build's process tree (pid $pid) ---"
  proc_tree "$pid"
  echo "--- this user's busiest processes ---"
  ps -u "$(id -un)" -o etime=,pcpu=,rss=,args= --sort=-pcpu 2> /dev/null \
    | cut -c 1-160 | head -n 20 || true
  echo "===== end of diagnostics ====="
}

