#!/usr/bin/env bash
# Usage: scripts/nightly/fix.sh <project>
#
# <project> failed to build against the F* that the nightly advanced to. Ask
# the Copilot CLI (in autopilot mode) to repair it, in the tree that the
# failed build left in $OLYMPUS_WORK/src/<project>; check, rather than
# trust, that it did; and then publish the fix:
#
#   1. Copilot edits the tree. It is given no credentials but its own, and
#      is told not to use git: nothing it does reaches a repository.
#   2. The project is rebuilt (scripts/run.sh), as many times as there are
#      attempts, each attempt resuming from the last one's tree and log.
#   3. The change is checked for the shortcuts that would make a proof
#      "work" by weakening it (admit, assume, --lax, ...), and rejected if it
#      has any.
#   4. It is committed and pushed to the project's `olympus` branch (created
#      if the project has none). Never forced: if the branch has moved, this
#      fails, and a human decides.
#   5. The pushed commit is then built again from scratch, which is what
#      will be recorded: the file $OLYMPUS_NIGHTLY_OUT/<project>.hash.
#
# Environment:
#   COPILOT_GITHUB_TOKEN   Copilot credentials (required)
#   OLYMPUS_PUSH_TOKEN     write access to the project (required)
#   OLYMPUS_FIX_ATTEMPTS   how many times Copilot may try (default 3)
#   OLYMPUS_FIX_CREDITS    AI credits it may spend on each try (default 200)
#   OLYMPUS_FIX_MODEL      the model (default claude-opus-5.5)
#   OLYMPUS_COPILOT_TIMEOUT  how long one try may take (default 90m)
#   OLYMPUS_FIX_DEADLINE   no new try starts after this long (default 300m)
#   OLYMPUS_NIGHTLY_OUT    where to leave logs and the result (default
#                          ./nightly-out)

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

p=${1:?usage: fix.sh <project>}
repo=$(repo_of "$p")
src=$(src_dir "$p")
logs=$OLYMPUS_WORK/logs
out=${OLYMPUS_NIGHTLY_OUT:-$PWD/nightly-out}
attempts=${OLYMPUS_FIX_ATTEMPTS:-3}
credits=${OLYMPUS_FIX_CREDITS:-200}
model=${OLYMPUS_FIX_MODEL:-claude-opus-5.5}
copilot_limit=${OLYMPUS_COPILOT_TIMEOUT:-90m}
deadline=$(timeout_secs "${OLYMPUS_FIX_DEADLINE:-300m}")
mkdir -p "$out" "$logs"

# Keep the credentials out of everything but the commands that need them:
# not the builds, which run arbitrary makefiles, and not the agent's git.
copilot_token=${COPILOT_GITHUB_TOKEN:-}
push_token=${OLYMPUS_PUSH_TOKEN:-}
unset COPILOT_GITHUB_TOKEN OLYMPUS_PUSH_TOKEN GH_TOKEN GITHUB_TOKEN

summary () { [ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"; return 0; }

stash_logs () {
  cp "$logs/$p".*.log "$logs/$p".*.md "$out/" 2> /dev/null || true
  [ -f "$logs/$p.log" ] && cp "$logs/$p.log" "$out/$p.last-build.log"
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
[ -n "$push_token" ]    || fail "OLYMPUS_PUSH_TOKEN is not set (see \"The nightly\" in README.md)"
command -v copilot > /dev/null || fail "the Copilot CLI is not installed"
[ -d "$src/.git" ] || fail "there is no tree at $src: the build that failed should have left it"

base=$(git -C "$src" rev-parse HEAD)
fstar_new=$(hash_of FStar)
fstar_old=$(git -C "$OLYMPUS_ROOT" show HEAD:hashes.txt 2> /dev/null \
            | sed -e 's/#.*//' | awk -F: '$1 == "FStar" { print $2 }')
fstar_old=${fstar_old:-unknown}

# What was already in the tree before Copilot touched it: the failed build's
# leftovers, which are not the fix.
untracked_before=$(mktemp)
git -C "$src" ls-files -o --exclude-standard | sort > "$untracked_before"

cp "$logs/$p.log" "$logs/$p.initial.log"

# Added lines that would make a proof pass by weakening it. Only in the files
# people write: the generated ones (extracted OCaml and C) are full of
# Obj.magic and friends.
shortcuts='admit_smt_queries|--lax|--admit|\badmit ?\(|\bmagic ?\(|\bassume ?\(|\bassume +val\b'
written_by_hand='\.fsti?$|\.fst\.config\.json$|(^|/)Makefile$|\.Makefile$|\.mk$|^\.github/'

# Whatever the agent created that was not there before.
agent_files () {
  git -C "$src" ls-files -o --exclude-standard | sort \
    | comm -13 "$untracked_before" -
}

find_shortcuts () {
  local f
  git -C "$src" diff HEAD -U0 \
    | RE="$written_by_hand" awk '
        /^\+\+\+ b\// { keep = (substr($0, 7) ~ ENVIRON["RE"]); next }
        keep && /^\+/ { print }' \
    | grep -E -- "$shortcuts" || true
  { agent_files | grep -E -- "$written_by_hand" || true; } | while read -r f; do
    grep -H -E -- "$shortcuts" "$src/$f" || true
  done
}

# Undo what the agent did, keeping what the failed build left.
discard_agent_work () {
  agent_files | while read -r f; do rm -f -- "$src/$f"; done
  git -C "$src" checkout -q -- . 2> /dev/null || true
}

prompt () {
  local n=$1 last=$2 old_hint=''
  [ "$fstar_old" != unknown ] && [ "$fstar_old" != "$fstar_new" ] && old_hint="
The F* that this project last built with is $fstar_old. The F* checkout at
$(src_dir FStar) has both, so 'git -C $(src_dir FStar) log $fstar_old..$fstar_new'
(and 'git diff' between them) says what changed in F*, Pulse and the F*
library. Consult it: a proof broken by an upgrade is usually fixed by
adapting to a change you can read there."
  cat <<EOF
You are repairing a project in OlympusMons, a collection of F* and Pulse
projects that are built together against one F*.

Tonight F* was advanced to its latest master, $fstar_new, and the project
$p ($repo, at $base) no longer builds with it. Your job is to change $p, and
only $p, so that it builds again. This is attempt $n of $attempts.
$old_hint
The current directory is the project's tree. It is what the failed build left,
so a build resumes rather than starting over: files that verified already
are not checked again.

  The log of the failed build:  $last
  What CI runs for this project: $OLYMPUS_ROOT/scripts/build/$p.sh
  The F* that it is built with:  $FSTAR_PKG  (binaries; do not modify)

Run anything in the project's build environment with:

  bash -c 'source $OLYMPUS_ROOT/scripts/lib.sh && olympus_env && cd $src && <command>'

(that puts the right fstar.exe, krml, z3 and opam switch on PATH). To check
a single file is much quicker than a whole build; use it while you work. The
whole build is:

  NOCHECKOUT=1 $OLYMPUS_ROOT/scripts/run.sh $p

which prints nothing until it ends, writes its log to $logs/$p.log, and
exits 0 exactly when the build succeeds. It may take over an hour. Finish
only when it exits 0, or when you are sure that you cannot get it to.

The likeliest causes are all upstream changes: a lemma that was renamed or
removed, a changed signature or implicit argument, a proof that no longer
goes through under a different SMT encoding or a changed tactic or
normalizer, a new warning that the project turns into an error, or an API of
Pulse that moved. Find the first error in the log, understand its cause, and
fix that. Work from the first error: later ones are often consequences.

Rules:

- Change files in this directory only. Do not touch $OLYMPUS_ROOT, the F*
  package or checkout, or any other project.
- Do not weaken what is proved. No admit, assume, magic, unsafe casts,
  --admit_smt_queries, --lax or similar, and do not delete, comment out or
  skip a lemma, a test or a module to make a failure go away. Adding or
  adapting a hint, an assertion, a lemma, an instantiation, a fuel or z3rlimit
  setting is fine, and so is moving to the new name or signature of
  something that changed upstream.
- Do not change the project's CI configuration (.github), or its pins of F*
  or any dependency; they are overridden here.
- Do not run git commit, git push or anything else that writes to a git
  repository, and you have no credentials to: the workflow commits what you
  leave in the tree, once it has checked it.
- Files that the build regenerates and that are committed (extracted C or
  OCaml, snapshots, dist/) are regenerated by the build: do not edit them by
  hand.
- Everything that is in the tree when you finish, and is not ignored by git,
  is committed. Delete any scratch files you made.
- Make the smallest change that works, in the style of the code around it.

If you cannot find a fix that you are confident in, change nothing more and
say why. A wrong fix is worse than none.

When you finish, say what the cause was, what you changed, and whether the
whole build passed.
EOF
}

# Run Copilot, with nothing in its environment that it does not need: not
# the push token, nor any GitHub credential that git or gh could use.
copilot_run () {
  local n=$1 limit
  limit=$(timeout_secs "$copilot_limit")
  prompt "$n" "$2" > "$logs/$p.prompt-$n.md"
  msg "$p: attempt $n: Copilot ($model, at most $credits AI credits, $(duration "$limit"))"
  local rc=0
  ( cd "$src" && timeout -k 60s "$limit" env \
      COPILOT_GITHUB_TOKEN="$copilot_token" \
      GH_CONFIG_DIR="$(mktemp -d)" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
      copilot -p "$(cat "$logs/$p.prompt-$n.md")" \
        --autopilot --yolo --no-ask-user --no-color \
        --model "$model" \
        --max-ai-credits "$credits" --max-autopilot-continues 50 \
        --share "$logs/$p.copilot-$n.md" \
        --log-dir "$logs/$p.copilot-$n.logs" ) \
    > >(tee "$logs/$p.copilot-$n.log") 2>&1 || rc=$?
  msg "$p: attempt $n: Copilot finished (exit status $rc)"
}

start=$(date +%s)
fixed=0
last=$logs/$p.initial.log
for n in $(seq 1 "$attempts"); do
  if [ "$(( $(date +%s) - start ))" -ge "$deadline" ]; then
    msg "$p: no time left for attempt $n"; break
  fi
  copilot_run "$n" "$last"

  bad=$(find_shortcuts)
  if [ -n "$bad" ]; then
    msg "$p: attempt $n: rejected, it weakens the proofs:"
    echo "$bad" >&2
    last=$logs/$p.attempt-$n.log
    { echo "The previous attempt was thrown away, because it added lines that weaken"
      echo "what is proved (admit, assume, magic, --lax, ...), which is not allowed:"
      echo "$bad"
      echo
      echo "The log of the build before it follows."; echo
      cat "$logs/$p.initial.log"; } > "$last"
    discard_agent_work
    continue
  fi

  rc=0
  NOCHECKOUT=1 "$OLYMPUS_ROOT/scripts/run.sh" "$p" || rc=$?
  cp "$logs/$p.log" "$logs/$p.attempt-$n.log"
  last=$logs/$p.attempt-$n.log
  if [ "$rc" = 0 ]; then fixed=1; break; fi
  msg "$p: attempt $n: the build still fails"
done

[ "$fixed" = 1 ] || fail "Copilot did not get $p to build in $attempts attempts (logs: the \`log-fix-$p\` artifact)."

# Commit what Copilot changed and what the build regenerated, but not what
# the failed build had left lying about.
git -C "$src" add -u
agent_files | while read -r f; do git -C "$src" add -- "$f"; done
if git -C "$src" diff --cached --quiet; then
  msg "$p: it builds with nothing changed (the failure did not reproduce)"
  echo "$base" > "$out/$p.hash"
  summary "### :white_check_mark: \`$p\`: builds now, with no change"
  summary ""
  summary "The failed build did not reproduce; it was probably transient."
  exit 0
fi

git -C "$src" diff --cached --stat | tail -n 20
run_url=${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-FStarLang/OlympusMons}/actions/runs/${GITHUB_RUN_ID:-0}
git -C "$src" -c user.name='OlympusMons nightly' \
    -c user.email='olympusmons-nightly@users.noreply.github.com' \
    commit -q -F - <<EOF
Adapt to F* ${fstar_new:0:12}

The OlympusMons nightly advanced F* to ${fstar_new:0:12} and found that this
project no longer built. This change was written by the GitHub Copilot CLI
($model, autopilot) and checked by building the project against that F*:
$run_url
EOF
new=$(git -C "$src" rev-parse HEAD)

git -C "$src" format-patch -1 --stdout > "$out/$p.fix.patch"

# Never forced; credentials only for this command.
msg "$p: pushing ${new:0:12} to $repo olympus"
# shellcheck disable=SC2016
env OLYMPUS_PUSH_TOKEN="$push_token" git \
    -c credential.helper= \
    -c 'credential.helper=!f() { echo username=x-access-token; echo "password=$OLYMPUS_PUSH_TOKEN"; }; f' \
    -C "$src" push origin "$new:refs/heads/olympus" \
  || fail "could not push to the \`olympus\` branch of $repo (has it moved? is the token allowed to write to it?). The fix is the \`$p.fix.patch\` in the artifact."

# What is recorded had better be what was built: build the commit, from
# scratch, as the run does for every project that needs no fix.
hashes=$(mktemp)
sed -E "s/^($p):[0-9a-f]+/\1:$new/" "$OLYMPUS_HASHES" > "$hashes"
msg "$p: building ${new:0:12} from scratch"
rc=0
OLYMPUS_HASHES=$hashes CLEAN=1 "$OLYMPUS_ROOT/scripts/run.sh" "$p" || rc=$?
cp "$logs/$p.log" "$logs/$p.final.log"
[ "$rc" = 0 ] || fail "the fix was pushed (\`${new:0:12}\`), but a build of it from scratch fails (log: \`$p.final.log\` in the artifact)."

echo "$new" > "$out/$p.hash"
summary "### :white_check_mark: \`$p\`: fixed"
summary ""
summary "[\`$repo@${new:0:12}\`](https://github.com/$repo/commit/$new), on the \`olympus\` branch, after ${n} attempt(s). Built from scratch against F* \`${fstar_new:0:12}\`."
summary ""
summary '```'
summary "$(git -C "$src" show --stat --format= "$new" | tail -n 30)"
summary '```'
msg "$p: fixed, at $new"
