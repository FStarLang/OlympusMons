#!/usr/bin/env bash
# Usage: scripts/run.sh <target>
#
# <target> is a project, or FStar-ci (F*'s own CI target, run in the F* tree
# that the FStar target built). Checks out the commit recorded in hashes.txt
# (unless NOCHECKOUT=1), runs scripts/build/<target>.sh with its output in
# _work/logs/<target>.log, and records the outcome in _work/status/<target>.

source "$(dirname "$0")/lib.sh"

t=$1
p=${t%-ci}
log=$OLYMPUS_WORK/logs/$t.log
status=$OLYMPUS_WORK/status/$t
mkdir -p "$OLYMPUS_WORK/logs" "$OLYMPUS_WORK/status"
rm -f "$status"

if [ "$t" = "$p" ] && [ "${NOCHECKOUT:-0}" != 1 ]; then
  "$OLYMPUS_ROOT/scripts/checkout.sh" "$p"
fi
rev=$(git -C "$(src_dir "$p")" rev-parse HEAD)

msg "$t: building $(repo_of "$p")@${rev:0:12} (log: $log)"
start=$(date +%s)
if "$OLYMPUS_ROOT/scripts/build/$t.sh" > "$log" 2>&1; then
  result=ok
else
  result=FAILED
fi
secs=$(( $(date +%s) - start ))
echo "$result $rev $secs" > "$status"
msg "$t: $result after $((secs / 60))m$((secs % 60))s"

if [ "$result" != ok ]; then
  tail -n 30 "$log" >&2
  exit 1
fi
