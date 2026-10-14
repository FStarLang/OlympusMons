#!/usr/bin/env bash
# Build Z3 from the recorded commit and install it in _work/z3, which is the
# only Z3 that F* and the projects can use: it is installed both as `z3` and
# as `z3-<version>` (the name under which F* looks for the Z3 of its
# --z3version). Every other `z3*` executable in PATH (e.g. a z3-4.13.3 that a
# project pins) is shadowed in _work/z3 by a stub that fails, so that a
# leftover pin of another Z3 version makes the build fail rather than
# silently use another Z3. An existing build of the current commit is reused,
# unless CLEAN=1.

source "$(dirname "$0")/../lib.sh"
cd "$(src_dir z3)"

rev=$(git rev-parse HEAD)
# 5.1.0.0 -> 5.1.0
ver=$(cut -d. -f1-3 scripts/VERSION.txt)

if [ "${CLEAN:-0}" = 1 ] || [ ! -x build/z3 ] \
   || [ "$(cat build/.olympus-rev 2> /dev/null)" != "$rev" ]; then
  rm -rf build
  cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DZ3_BUILD_LIBZ3_SHARED=OFF
  ninja -C build -j"$JOBS" z3
  echo "$rev" > build/.olympus-rev
fi

rm -rf "$Z3_BIN"
mkdir -p "$Z3_BIN"
cp build/z3 "$Z3_BIN/z3"
ln -s z3 "$Z3_BIN/z3-$ver"

# The stubs. The fixed names are the versions that F* and the projects have
# pinned, in case they are not in this PATH but appear in another one.
stub_names=(z3-4.8.5 z3-4.13.3 z3-4.15.3 z3-4.15.4 z3-4.15.5 z3-5.0.0)
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
