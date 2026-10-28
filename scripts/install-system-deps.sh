#!/usr/bin/env bash
# Usage: sudo scripts/install-system-deps.sh
#
# Install the system packages that F* and the projects need, on Ubuntu 24.04
# (e.g. on a new CI runner; see README.md): the union of what their own CIs
# install. Rust is not installed here: install it with rustup
# (https://rustup.rs) as the user who runs the builds, as pal needs a more
# recent version than Ubuntu's.

set -euo pipefail

if [ "$(id -u)" != 0 ]; then
  echo "run this script as root: sudo $0" >&2
  exit 1
fi
. /etc/os-release
if [ "$ID $VERSION_ID" != "ubuntu 24.04" ]; then
  echo "warning: this script is meant for Ubuntu 24.04, not $PRETTY_NAME" >&2
fi

pkgs=(
  # F* (see its .github/actions/setup-fstar-deps) and opam
  build-essential ca-certificates curl dotnet-sdk-10.0 git jq libffi-dev
  libgmp-dev m4 opam pkg-config python-is-python3 python3 rsync time unzip
  wget
  # Cloning the private repositories
  gh
  # EverParse's tests (see its Dockerfile and CI)
  clang cmake gcc-multilib libsqlite3-dev libssl-dev python3-pip
  python3-venv
  # apt.llvm.org's installer (below)
  gnupg lsb-release software-properties-common
)
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q --no-install-recommends "${pkgs[@]}"

# F*'s Cherry C backend needs GCC 15 (as gcc-15, beside the system GCC),
# from the toolchain PPA, as in F*'s CI.
add-apt-repository -y ppa:ubuntu-toolchain-r/test
apt-get update -q
apt-get install -y -q --no-install-recommends gcc-15 g++-15

# pal needs clang/LLVM 20, and checks its formatting with clang-format 20.
# Install them from apt.llvm.org, as its CI and F*'s check-friends.yml do.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
wget -q -O "$tmp/llvm.sh" https://apt.llvm.org/llvm.sh
bash "$tmp/llvm.sh" 20
apt-get install -y -q --no-install-recommends \
  clang-20 clang-format-20 clang-tools-20 libclang-20-dev libclang-cpp20-dev \
  llvm-20-dev
ln -sf /usr/bin/clang-format-20 /usr/local/bin/clang-format
