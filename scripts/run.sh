#!/usr/bin/env bash
# Usage: scripts/run.sh <target>
#
# <target> is a project, or FStar-ci (F*'s own CI target, run in the F* tree
# that the FStar target built). Checks out the commit recorded in hashes.txt
# (unless NOCHECKOUT=1), runs scripts/build/<target>.sh with its output in
# _work/logs/<target>.log, and records the outcome in _work/status/<target>.
#
# While the build runs, its progress is reported every $OLYMPUS_HEARTBEAT
# seconds, so that a long build is visibly alive and a stuck one is visibly
# stuck. A build that exceeds $OLYMPUS_TIMEOUT is killed, but not before the
# state of the machine (the process tree in particular) has been appended to
# its log: that record is what says *which* command hung.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

t=$1
p=${t%-ci}
log=$OLYMPUS_WORK/logs/$t.log
# Where the watchdog records the state of the machine. Kept apart from the
# log so that the build, which is still writing, cannot interleave with it.
diag=$OLYMPUS_WORK/logs/$t.diagnostics.log
status=$OLYMPUS_WORK/status/$t
mkdir -p "$OLYMPUS_WORK/logs" "$OLYMPUS_WORK/status"
rm -f "$status" "$diag"
# Create the log now, so that it exists (and so is collected and uploaded)
# even if we never get as far as starting the build.
: > "$log"

# A project is built against the trees of its dependencies, so they must
# have built, and (unless NOCHECKOUT=1, when the trees are what they are) at
# the commits recorded for them.
for d in $(deps_of "$p"); do
  dres='not built' drev=''
  [ -f "$OLYMPUS_WORK/status/$d" ] && read -r dres drev _ < "$OLYMPUS_WORK/status/$d"
  want=$(hash_of "$d")
  if [ "$dres" != ok ] || { [ "${NOCHECKOUT:-0}" != 1 ] && [ "$drev" != "$want" ]; }; then
    echo "[olympus] $t: needs $d built at ${want:0:12}, but its last build is: $dres ${drev:0:12}" \
      | tee -a "$log" >&2
    echo "BLOCKED $(hash_of "$p") 0" > "$status"
    exit 1
  fi
done

if [ "$t" = "$p" ] && [ "${NOCHECKOUT:-0}" != 1 ]; then
  # In the log as well as on the console: a checkout that fails (a
  # repository the runner cannot read, say) must leave the same evidence
  # behind as a build that fails.
  if ! "$OLYMPUS_ROOT/scripts/checkout.sh" "$p" 2>&1 | tee -a "$log" >&2; then
    echo "FAILED $(hash_of "$p") 0" > "$status"
    msg "$t: could not check out $(repo_of "$p")"
    exit 1
  fi
fi
rev=$(git -C "$(src_dir "$p")" rev-parse HEAD)

# The nightly could not rebase this project's `olympus` branch onto its
# upstream (see nightly/advance.sh), so what is checked out is the old
# `olympus` tip, which is not worth hours of building: fix.sh rebases.
if [ "$t" = "$p" ] && [ "${NOCHECKOUT:-0}" != 1 ] \
   && [ "$(rebase_info "$p" result)" = conflict ] \
   && [ "$rev" = "$(rebase_info "$p" olympus)" ]; then
  { echo "[olympus] $p: the olympus branch does not rebase cleanly onto" \
         "$(rebase_info "$p" branch) ($(rebase_info "$p" upstream)); not built."
    cat "$OLYMPUS_WORK/nightly/rebase/$p.rebase.log" 2> /dev/null || true
  } >> "$log"
  echo "CONFLICT $rev 0" > "$status"
  msg "$t: CONFLICT (the olympus branch does not rebase onto upstream)"
  exit 1
fi

OLYMPUS_TIMEOUT=$(timeout_of "$t")
limit=$(timeout_secs "$OLYMPUS_TIMEOUT")

msg "$t: building $(repo_of "$p")@${rev:0:12} (log: $log)"
msg "$t: at most $OLYMPUS_TIMEOUT, with $JOBS parallel jobs"
start=$(date +%s)

# Say that the build is alive, and what it is up to, every so often. Without
# this a job's log is silent for an hour at a time, and a hung build looks
# exactly like a slow one.
heartbeat () {
  local last
  while sleep "$OLYMPUS_HEARTBEAT"; do
    last=$(tail -c 2000 "$log" 2> /dev/null | tr -d '\r' \
           | grep -v '^[[:space:]]*$' | tail -n 1 | cut -c 1-120)
    msg "$t: still running after $(elapsed "$start") -- ${last:-(no output yet)}"
  done
}

# Record what the machine is doing shortly before the build is killed: once
# `timeout` has fired, the process tree that would say what hung is gone.
watchdog () {
  # A minute's warning, or a tenth of the budget if that is shorter.
  local lead=$((limit / 10))
  [ "$lead" -gt 60 ] && lead=60
  [ "$lead" -lt 1 ] && lead=1
  sleep "$((limit - lead))"
  msg "$t: about to hit the $OLYMPUS_TIMEOUT limit; recording what it is doing"
  { echo "[olympus] $t: still running after $(elapsed "$start"); killing it" \
         "in ${lead}s. What the machine was doing:"
    diagnose "$$"
  } > "$diag" 2>&1
}

heartbeat & hb=$!
watchdog & wd=$!
trap 'kill "$hb" "$wd" 2> /dev/null; exit' EXIT INT TERM

# `timeout` runs the build in its own process group and signals the whole
# group, so the children of make are killed too, and -k guarantees a KILL
# if the build ignores the TERM.
rc=0
timeout -k 60s "$OLYMPUS_TIMEOUT" "$OLYMPUS_ROOT/scripts/build/$t.sh" \
  >> "$log" 2>&1 || rc=$?
kill "$hb" "$wd" 2> /dev/null || true
trap - EXIT INT TERM

case $rc in
  0)       result=ok ;;
  124|137) result=TIMEOUT ;;
  *)       result=FAILED ;;
esac
secs=$(( $(date +%s) - start ))
echo "$result $rev $secs" > "$status"
msg "$t: $result after $(elapsed "$start")"

if [ "$result" != ok ]; then
  if [ "$result" = TIMEOUT ] && [ -s "$diag" ]; then
    msg "$t: killed after $OLYMPUS_TIMEOUT (raise \$OLYMPUS_TIMEOUT to allow" \
        "more); below is what it was doing when it was killed"
    # Also in the log, whose tail is what the job summary shows.
    cat "$diag" >> "$log"
    group "What $t was doing when it timed out" cat "$diag" >&2
  fi
  group "The last 100 lines of $log" tail -n 100 "$log" >&2
  exit 1
fi
