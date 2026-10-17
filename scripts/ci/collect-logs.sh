#!/usr/bin/env bash
# Usage: scripts/ci/collect-logs.sh [<target>...]
#
# Copy the logs of the given targets (all of them by default) out of the
# shared build tree and into ci-logs/ in the workspace, where
# actions/upload-artifact can pick them up with a relative path.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

dest=${OLYMPUS_LOG_DEST:-$OLYMPUS_ROOT/ci-logs}
mkdir -p "$dest"

targets=("$@")
[ "${#targets[@]}" = 0 ] && targets=("${TARGETS[@]}")

for t in "${targets[@]}"; do
  for f in "$OLYMPUS_WORK/logs/$t.log" "$OLYMPUS_WORK/logs/$t.diagnostics.log"; do
    [ -f "$f" ] && cp -p "$f" "$dest/"
  done
done

if [ -z "$(ls -A "$dest")" ]; then
  msg "no logs to collect for: ${targets[*]}"
else
  msg "collected $(du -sh "$dest" | cut -f1) of logs:"
  ls -lh "$dest" >&2
fi
