#!/usr/bin/env bash
# F*'s own CI target.

source "$(dirname "$0")/../lib.sh"
base_env
cd "$(src_dir FStar)"

pmake ci
