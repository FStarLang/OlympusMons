#!/usr/bin/env bash
# AlgoStar: its CI (.github/workflows/ci.yml) verifies autoclrs/.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"
olympus_env
cd "$(src_dir AlgoStar)"

pmake -C autoclrs
