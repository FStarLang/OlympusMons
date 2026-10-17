#!/usr/bin/env bash
# Install the Z3 of the recorded commit in _work/z3, which is the only Z3
# that F* and the projects can use: it is installed both as `z3` and as
# `z3-<version>` (the name under which F* looks for the Z3 of its
# --z3version). Every other `z3*` executable in PATH (e.g. a z3-4.13.3 that a
# project pins) is shadowed in _work/z3 by a stub that fails, so that a
# leftover pin of another Z3 version makes the build fail rather than
# silently use another Z3.
#
# If the recorded commit is a Z3 release (tagged z3-<version>) and there is
# an official executable of that release for this platform, that executable
# is installed (the one that F* bundles; see F*'s .scripts/get_fstar_z3.sh),
# unless Z3_FROM_SOURCE=1. Otherwise Z3 is built from source. An existing
# download or build of the current commit is reused, unless CLEAN=1.

source "$(dirname "$0")/../lib.sh"
cd "$(src_dir z3)"

rev=$(git rev-parse HEAD)
# 5.3.0.0 -> 5.3.0
ver=$(cut -d. -f1-3 scripts/VERSION.txt)

# The official executable of release $1 for this platform, if any.
release_url () {
  local base=https://github.com/Z3Prover/z3/releases/download/z3-$1
  case "$(uname -s)-$(uname -m)" in
    # The standalone executable in the wheel also runs on older glibcs.
    Linux-x86_64) echo "$base/z3_solver-$1.0-py3-none-manylinux_2_27_x86_64.whl" ;;
  esac
}

url=
if ! git rev-parse -q --verify "refs/tags/z3-$ver" > /dev/null; then
  git_auth fetch -q origin "+refs/tags/z3-$ver:refs/tags/z3-$ver" 2> /dev/null || true
fi
if [ "${Z3_FROM_SOURCE:-0}" != 1 ] \
   && [ "$(git rev-parse -q --verify "refs/tags/z3-$ver^{commit}")" = "$rev" ]; then
  url=$(release_url "$ver")
fi

if [ -n "$url" ]; then
  z3=$OLYMPUS_WORK/z3-release/z3
  stamp="$rev $url"
  if [ "${CLEAN:-0}" = 1 ] || [ ! -x "$z3" ] \
     || [ "$(cat "$z3.olympus-rev" 2> /dev/null)" != "$stamp" ]; then
    msg "z3: downloading release $ver from $url"
    rm -rf "$OLYMPUS_WORK/z3-release"
    mkdir -p "$OLYMPUS_WORK/z3-release"
    tmp=$(mktemp -d)
    curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors "$url" -o "$tmp/z3.pkg"
    sha256sum "$tmp/z3.pkg"
    case "$url" in
      *.whl) unzip -q -d "$tmp" "$tmp/z3.pkg" "z3_solver-$ver.0.data/data/bin/z3"
             install -m0755 "$tmp/z3_solver-$ver.0.data/data/bin/z3" "$z3" ;;
    esac
    rm -rf "$tmp"
    echo "$stamp" > "$z3.olympus-rev"
  fi
else
  z3=$PWD/build/z3
  if [ "${CLEAN:-0}" = 1 ] || [ ! -x build/z3 ] \
     || [ "$(cat build/.olympus-rev 2> /dev/null)" != "$rev" ]; then
    rm -rf build
    cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DZ3_BUILD_LIBZ3_SHARED=OFF
    ninja -C build -j"$JOBS" z3
    echo "$rev" > build/.olympus-rev
  fi
fi

if [ "$("$z3" --version | awk '{ print $3 }')" != "$ver" ]; then
  echo "z3: $z3 is not Z3 $ver: $("$z3" --version)" >&2
  exit 1
fi

rm -rf "$Z3_BIN"
mkdir -p "$Z3_BIN"
cp "$z3" "$Z3_BIN/z3"
ln -s z3 "$Z3_BIN/z3-$ver"

# The stubs. The fixed names are the versions that F* and the projects have
# pinned, in case they are not in this PATH but appear in another one.
stub_names=(z3-4.8.5 z3-4.13.3 z3-4.15.3 z3-4.15.4 z3-4.15.5 z3-5.0.0 z3-5.1.0)
IFS=: read -ra dirs <<< "$PATH"
for d in "${dirs[@]}"; do
  for f in "$d"/z3 "$d"/z3-*; do
    [ -x "$f" ] && [ ! -d "$f" ] && stub_names+=("${f##*/}")
  done
done
for n in "${stub_names[@]}"; do
  [ -e "$Z3_BIN/$n" ] && continue
  cat > "$Z3_BIN/$n" <<EOF
#!/bin/sh
echo "olympus: '$n' is not the Z3 under test; use z3 or z3-$ver (Z3 $rev)" >&2
exit 127
EOF
  chmod +x "$Z3_BIN/$n"
done

"$Z3_BIN/z3-$ver" --version
ls "$Z3_BIN"
