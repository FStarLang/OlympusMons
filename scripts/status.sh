#!/usr/bin/env bash
# Usage: scripts/status.sh
#
# Summarize the last build of each target, and whether it was built from
# the commit currently recorded in hashes.txt.

source "$(dirname "$0")/lib.sh"

printf '%-18s %-7s %-13s %-9s %s\n' TARGET RESULT COMMIT TIME NOTE
for t in z3 FStar FStar-ci "${PROJECTS[@]:2}"; do
  p=${t%-ci}
  f=$OLYMPUS_WORK/status/$t
  if [ ! -f "$f" ]; then
    printf '%-18s %-7s\n' "$t" '-'
    continue
  fi
  read -r result rev secs < "$f"
  note=
  if [ "$rev" != "$(hash_of "$p")" ]; then
    note="(not the commit in hashes.txt)"
  fi
  printf '%-18s %-7s %-13s %-9s %s\n' "$t" "$result" "${rev:0:12}" \
    "$((secs / 60))m$((secs % 60))s" "$note"
done
