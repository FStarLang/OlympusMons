#!/usr/bin/env bash
# Usage: scripts/nightly/apply-fixes.sh <candidate-hashes> <fixed-dir> <out>
#
# <out> is <candidate-hashes> with, for every <fixed-dir>/<project>.hash,
# that project's line replaced by the commit of its fix.

set -euo pipefail

candidate=${1:?usage: apply-fixes.sh <candidate-hashes> <fixed-dir> <out>}
fixed=${2:?}
out=${3:?}

cp "$candidate" "$out"
for f in "$fixed"/*.hash; do
  [ -e "$f" ] || continue
  p=$(basename "$f" .hash)
  sed -E -i "s/^($p):[0-9a-f]+/\1:$(cat "$f")/" "$out"
done
diff "$candidate" "$out" || true
