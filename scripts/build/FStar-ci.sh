#!/usr/bin/env bash
# F*'s own CI target.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"
base_env
cd "$(src_dir FStar)"

pmake ci
