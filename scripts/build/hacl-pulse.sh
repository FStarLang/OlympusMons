#!/usr/bin/env bash
# hacl-pulse has no CI; its default target verifies everything, extracts
# dist/ (with Custard), compiles it and runs the C tests. The extracted
# dist/ is committed, so it must also be up to date.

source "$(dirname "$0")/../lib.sh"
olympus_env
cd "$(src_dir hacl-pulse)"

pmake FSTAR_EXE="$FSTAR_EXE"

if ! git diff --quiet -- dist/; then
  msg "hacl-pulse: the committed dist/ differs from the extracted one:"
  git diff --stat -- dist/ >&2
  exit 1
fi
