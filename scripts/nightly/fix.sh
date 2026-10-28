#!/usr/bin/env bash
# Usage: scripts/nightly/fix.sh <project>
#
# <project> failed to build against the F* that the nightly advanced to. Run
# the Copilot CLI (autopilot, once) in the tree that the failed build left in
# $OLYMPUS_WORK/src/<project>. The agent builds the project as often as it
# needs to, and finishes when the build passes or when it gives up. This
# script then checks, rather than trusts, what it left:
#
#   * the agent's last build must have succeeded (the status that run.sh
#     records), and
#   * the change must not have the shortcuts that make a proof "work" by
#     weakening it (admit, assume, --lax, ...).
#
# If the nightly could not rebase the project's `olympus` branch onto its
# upstream (see advance.sh), the tree is at the old `olympus` tip, nothing
# was built, and the agent's first job is to finish that rebase: this script
# starts it, the agent resolves the conflicts, and the result must then be
# a linear history on top of upstream, without conflict markers.
#
# If so, the change is committed *locally*, and the commit is left in
# $OLYMPUS_NIGHTLY_OUT/<project>.hash. Nothing is pushed here: the same job
# then builds the commit from scratch (see nightly-project.yml), and only if
# every project builds does the Publish job push the commits to the
# `olympus` branches and record them.
#
# The agent has no credentials but its own, and is told not to use git (but
# to finish the rebase, if there is one).
#
# Environment:
#   COPILOT_GITHUB_TOKEN     Copilot credentials (required)
#   OLYMPUS_FIX_MODEL        the model (default claude-opus-5.5)
#   OLYMPUS_COPILOT_TIMEOUT  how long the agent may run before it is stopped
#                            (default 12h; not a budget, a guard against a
#                            hung session)
#   OLYMPUS_NIGHTLY_OUT      where to leave logs and the result (default
#                            ./nightly-out)

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

p=${1:?usage: fix.sh <project>}
repo=$(repo_of "$p")
src=$(src_dir "$p")
logs=$OLYMPUS_WORK/logs
out=${OLYMPUS_NIGHTLY_OUT:-$PWD/nightly-out}
model=${OLYMPUS_FIX_MODEL:-claude-opus-5.5}
limit=$(timeout_secs "${OLYMPUS_COPILOT_TIMEOUT:-12h}")
mkdir -p "$out" "$logs"

# Nothing that runs here but Copilot gets a credential.
copilot_token=${COPILOT_GITHUB_TOKEN:-}
unset COPILOT_GITHUB_TOKEN OLYMPUS_PUSH_TOKEN_FSTARLANG OLYMPUS_PUSH_TOKEN_PROJECT_EVEREST GH_TOKEN GITHUB_TOKEN

summary () { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"; return 0; }

stash_logs () {
  cp "$logs/$p".*.log "$logs/$p".*.md "$out/" 2> /dev/null || true
  return 0
}
trap stash_logs EXIT

fail () {
  msg "$p: $*"
  summary "### :x: \`$p\`: not fixed"
  summary ""
  summary "$*"
  exit 1
}

[ -n "$copilot_token" ] || fail "COPILOT_GITHUB_TOKEN is not set (see \"The nightly\" in README.md)"
command -v copilot > /dev/null || fail "the Copilot CLI is not installed"
[ -d "$src/.git" ] || fail "there is no tree at $src: the build that failed should have left it"

base=$(git -C "$src" rev-parse HEAD)
rebasing=0
[ "$(rebase_info "$p" result)" = conflict ] && rebasing=1
upstream=$(rebase_info "$p" upstream)
branch=$(rebase_info "$p" branch)
olympus_old=$(rebase_info "$p" olympus)
# What the agent's change is measured against: the commit it started from,
# or when it rebases, the upstream commit that it rebases onto.
from=$base
[ "$rebasing" = 1 ] && from=$upstream
fstar_new=$(hash_of FStar)
fstar_old=$(git -C "$OLYMPUS_ROOT" show HEAD:hashes.txt 2> /dev/null \
            | sed -e 's/#.*//' | awk -F: '$1 == "FStar" { print $2 }')
fstar_old=${fstar_old:-unknown}

# What was already in the tree before Copilot touched it: the failed build's
# leftovers, which are not the fix.
untracked_before=$(mktemp)
git -C "$src" ls-files -o --exclude-standard | sort > "$untracked_before"

# run.sh truncates its log, and the agent will run it.
cp "$logs/$p.log" "$logs/$p.initial.log"

# Added lines that would make a proof pass by weakening it. Only in the files
# people write: the generated ones (extracted OCaml and C) are full of
# Obj.magic and friends.
# Lines that the change may add although they match: when rebasing, the ones
# that the `olympus` branch already added (and that were checked then).
allowed=$(mktemp)
shortcuts='admit_smt_queries|--lax|--admit|\badmit ?\(|\bmagic ?\(|\bassume ?\(|\bassume +val\b'
written_by_hand='\.fsti?$|\.fst\.config\.json$|(^|/)Makefile$|\.Makefile$|\.mk$|^\.github/'

# Whatever the agent created that was not there before.
agent_files () {
  git -C "$src" ls-files -o --exclude-standard | sort \
    | comm -13 "$untracked_before" -
}

# The lines that `git diff <args>` adds to the files written by hand.
added_by_hand () {
  git -C "$src" diff -U0 "$@" \
    | RE="$written_by_hand" awk '
        /^\+\+\+ / { keep = (substr($0, 7) ~ ENVIRON["RE"]); next }
        keep && /^\+/ { print }'
}

find_shortcuts () {
  local f
  added_by_hand "$from" | grep -E -- "$shortcuts" | grep -vxF -f "$allowed" || true
  { agent_files | grep -E -- "$written_by_hand" || true; } | while read -r f; do
    grep -H -E -- "$shortcuts" "$src/$f" || true
  done
}

if [ "$rebasing" = 1 ]; then
  [ "$base" = "$olympus_old" ] \
    || fail "the tree is at ${base:0:12}, not at the olympus tip ${olympus_old:0:12} that does not rebase"
  added_by_hand "$(git -C "$src" merge-base "$olympus_old" "$upstream")" "$olympus_old" \
    | grep -E -- "$shortcuts" > "$allowed" || true
  # It stops at the first conflict, for the agent to resolve.
  if git -C "$src" "${NIGHTLY_GIT_ID[@]}" rebase "$upstream" > "$logs/$p.rebase.log" 2>&1; then
    msg "$p: the olympus branch rebases cleanly onto $branch now"
  fi
fi

rebase_task=''
if [ "$rebasing" = 1 ]; then
  rebase_task="
But first: the project's \`olympus\` branch, which has the changes that
OlympusMons needs on top of the project's own $branch branch, has to move to
the new tip of $branch, $upstream. That is a rebase, and it stopped with
conflicts. The rebase is in progress in this tree ('git status' says
where). Finish it:

  - Resolve each conflict, keeping what the \`olympus\` commit was for on
    top of the new upstream code. Upstream may have made the same change, or
    changed the code that it adapted; read both sides ('git log' and 'git
    diff' work, and so does 'git show REBASE_HEAD').
  - 'git add' (or 'git rm') the resolved files, then
    'GIT_EDITOR=true git rebase --continue'. Repeat until it is done.
  - 'git rebase --skip' only a commit that upstream already has. Never
    'git rebase --abort', and do not make merge commits.

Only then build the project, and fix it as below. Do not amend the rebased
commits: leave your fixes to the build uncommitted, as the rules say.
"
fi

fstar_hint=''
if [ "$fstar_old" != unknown ] && [ "$fstar_old" != "$fstar_new" ]; then
  fstar_hint="
The F* that this project last built with is $fstar_old. The F* checkout at
$(src_dir FStar) has both, so 'git -C $(src_dir FStar) log $fstar_old..$fstar_new'
(and 'git diff' between them) says what changed in F*, Pulse and the F*
library. Consult it: a proof broken by an upgrade is usually fixed by
adapting to a change you can read there.
"
fi

deps_rule=''
deps=$(deps_of "$p")
if [ -n "$deps" ]; then
  deps_rule="
  $p is built against the trees of$(for d in $deps; do printf ' %s' "$(src_dir "$d")"; done)
  (as their own builds left them, and they have been built): read them, but
  they are other projects, and so read-only too."
fi

prompt () {
  cat <<EOF
You are repairing a project in OlympusMons, a collection of F* and Pulse
projects that are built together against one F*.

Tonight F* was advanced to its latest master, $fstar_new, and the project
$p ($repo, at $base) no longer builds with it. Your job is to change $p, and
only $p, so that it builds again.
$rebase_task$fstar_hint
The current directory is the project's tree. It is what the failed build left,
so a build resumes rather than starting over: files that verified already
are not checked again.

  The log of the failed build:  $logs/$p.initial.log
  What CI runs for this project: $OLYMPUS_ROOT/scripts/build/$p.sh
  The F* that it is built with:  $FSTAR_PKG  (binaries; do not modify)

Run anything in the project's build environment with:

  bash -c 'source $OLYMPUS_ROOT/scripts/lib.sh && olympus_env && cd $src && <command>'

(that puts the right fstar.exe, krml, z3 and opam switch on PATH). To check
a single file is much quicker than a whole build; use it while you work. The
whole build is:

  NOCHECKOUT=1 $OLYMPUS_ROOT/scripts/run.sh $p

which prints nothing until it ends, writes its log to $logs/$p.log, and
exits 0 exactly when the build succeeds. It may take over an hour. Run it as
often as you need to. You have as long as it takes: keep going until it
exits 0, and only stop short of that if you are sure that you cannot get it
to. When you stop, the last whole build you ran is taken to be the state of
the tree, so do not leave the tree changed after your last passing build.

The likeliest causes are all upstream changes: a lemma that was renamed or
removed, a changed signature or implicit argument, a proof that no longer
goes through under a different SMT encoding or a changed tactic or
normalizer, a new warning that the project turns into an error, or an API of
Pulse that moved. Find the first error in the log, understand its cause, and
fix that. Work from the first error: later ones are often consequences.

Rules:

- Change files in this directory only. Do not touch $OLYMPUS_ROOT, the F*
  package or checkout, or any other project.$deps_rule
- Do not weaken what is proved. No admit, assume, magic, unsafe casts,
  --admit_smt_queries, --lax or similar, and do not delete, comment out or
  skip a lemma, a test or a module to make a failure go away. Adding or
  adapting a hint, an assertion, a lemma, an instantiation, a fuel or z3rlimit
  setting is fine, and so is moving to the new name or signature of
  something that changed upstream.
- Do not change the project's CI configuration (.github), or its pins of F*
  or any dependency; they are overridden here.
- Do not run git commit, git push or anything else that writes to a git
  repository (other than finishing the rebase, if there is one), and you
  have no credentials to push: the workflow commits what you leave in the
  tree, once it has checked it.
- Files that the build regenerates and that are committed (extracted C or
  OCaml, snapshots, dist/) are regenerated by the build: do not edit them by
  hand.
- Everything that is in the tree when you finish, and is not ignored by git,
  is committed. Delete any scratch files you made.
- Make the smallest change that works, in the style of the code around it.

Your change will be built again, from scratch, before it is used. If you
cannot find a fix that you are confident in, change nothing more and say
why. A wrong fix is worse than none.

When you finish, say what the cause was, what you changed, and whether the
whole build passed.
EOF
}

prompt > "$logs/$p.prompt.md"
msg "$p: running Copilot ($model, autopilot, no credit cap, stopped after $(duration "$limit"))"
rc=0
# Nothing in its environment that it does not need: no GitHub credential
# that git or gh could use. When it rebases, git needs a committer.
git_id=()
[ "$rebasing" = 1 ] && git_id=(
  GIT_COMMITTER_NAME='OlympusMons nightly'
  GIT_COMMITTER_EMAIL='olympusmons-nightly@users.noreply.github.com'
  GIT_EDITOR=true)
( cd "$src" && timeout -k 60s "$limit" env \
    COPILOT_GITHUB_TOKEN="$copilot_token" "${git_id[@]}" \
    GH_CONFIG_DIR="$(mktemp -d)" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    copilot -p "$(cat "$logs/$p.prompt.md")" \
      --autopilot --yolo --no-ask-user --no-color \
      --model "$model" \
      --max-autopilot-continues 100000 \
      --share "$logs/$p.copilot.md" \
      --log-dir "$logs/$p.copilot.logs" ) \
  > >(tee "$logs/$p.copilot.log") 2>&1 || rc=$?
msg "$p: Copilot finished (exit status $rc)"

# Its last whole build.
result=none
[ -f "$OLYMPUS_WORK/status/$p" ] && read -r result _ < "$OLYMPUS_WORK/status/$p"
cp "$logs/$p.log" "$logs/$p.agent-last-build.log" 2> /dev/null || true
if [ "$result" != ok ]; then
  fail "Copilot did not get $p to build (its last build: $result; Copilot exit status $rc). Its transcript and logs are in the \`log-fix-$p\` artifact."
fi

if [ "$rebasing" = 1 ]; then
  gitdir=$(git -C "$src" rev-parse --absolute-git-dir)
  if [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; then
    fail "Copilot did not finish rebasing the olympus branch onto $branch."
  fi
  git -C "$src" merge-base --is-ancestor "$upstream" HEAD \
    || fail "the result is not on top of $branch (${upstream:0:12})."
  [ -z "$(git -C "$src" rev-list --merges "$upstream..HEAD")" ] \
    || fail "the rebased olympus branch has merge commits."
  markers=$(git -C "$src" diff -U0 "$upstream" | grep -E '^\+(<<<<<<<|>>>>>>>)( |$)|^\+=======$' || true)
  [ -z "$markers" ] || fail "the rebase left conflict markers:
\`\`\`
$markers
\`\`\`"
fi

bad=$(find_shortcuts)
if [ -n "$bad" ]; then
  echo "$bad" | tee "$logs/$p.rejected.txt" >&2
  fail "the change weakens the proofs, which is not allowed:
\`\`\`
$bad
\`\`\`"
fi

# Commit what Copilot changed and what the build regenerated, but not what
# the failed build had left lying about. Locally only.
git -C "$src" add -u
agent_files | while read -r f; do git -C "$src" add -- "$f"; done
if git -C "$src" diff --cached --quiet && [ "$rebasing" = 0 ]; then
  msg "$p: it builds with nothing changed (the failure did not reproduce)"
  echo "$base" > "$out/$p.hash"
  summary "### :white_check_mark: \`$p\`: builds now, with no change"
  summary ""
  summary "The failed build did not reproduce; it was probably transient."
  exit 0
fi

run_url=${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-FStarLang/OlympusMons}/actions/runs/${GITHUB_RUN_ID:-0}
# When it rebased, the rebased commits may be all there is to it.
if ! git -C "$src" diff --cached --quiet; then
  git -C "$src" diff --cached --stat | tail -n 20
  git -C "$src" "${NIGHTLY_GIT_ID[@]}" commit -q -F - <<EOF
Adapt to F* ${fstar_new:0:12}

The OlympusMons nightly advanced F* to ${fstar_new:0:12} and found that this
project no longer built. This change was written by the GitHub Copilot CLI
($model, autopilot) and checked by building the project against that F*:
$run_url
EOF
fi
new=$(git -C "$src" rev-parse HEAD)
# Kept alive until the Publish job pushes it.
git -C "$src" update-ref refs/olympus/fix "$new"
git -C "$src" format-patch --stdout "$from..$new" > "$out/$p.fix.patch"
echo "$new" > "$out/$p.hash"

summary "### :white_check_mark: \`$p\`: Copilot got it to build"
summary ""
if [ "$rebasing" = 1 ]; then
  summary "Copilot rebased the olympus branch onto \`$branch\` (\`${upstream:0:12}\`): \`${new:0:12}\`, $(git -C "$src" rev-list --count "$upstream..$new") commit(s) on top of it."
else
  summary "\`${new:0:12}\` (on \`$base\`)."
fi
summary "Not pushed yet: it is built from scratch next, and pushed to \`$repo\` only if everything works."
summary ""
summary '```'
summary "$(git -C "$src" diff --stat "$from" "$new" | tail -n 30)"
summary '```'
msg "$p: committed ${new:0:12}, to be verified"
