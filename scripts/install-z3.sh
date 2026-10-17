#!/usr/bin/env bash
# Usage: scripts/install-z3.sh
#
# Install in _work/z3 the Z3 that the recorded F* uses by default (its
# --z3version), as `z3` and as `z3-<version>`: the official release
# executable, downloaded by F*'s own .scripts/get_fstar_z3.sh. This is the
# only Z3 that F* and the projects can use. Every other version that F*
# knows of, and every other `z3*` executable in PATH (e.g. a z3-4.13.3 that a
# project pins), is shadowed in _work/z3 by a stub that fails, so that a
# leftover pin of another Z3 version makes the build fail rather than
# silently use another Z3.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

fstar=$(src_dir FStar)
ver=$(sed -nE 's/^ *\("z3version" *, *String "([0-9.]+)"\);.*/\1/p' \
        "$fstar/src/basic/FStarC.Options.fst")
if [ -z "$ver" ]; then
  echo "install-z3: cannot find F*'s default --z3version in $fstar" >&2
  exit 1
fi

# get_fstar_z3.sh skips the versions already in its destination, so it gets
# a directory of its own, holding only real downloads (official releases,
# which never change, and so are kept from one build to the next).
dl=$OLYMPUS_WORK/z3-releases
"$fstar/.scripts/get_fstar_z3.sh" "$dl"
z3=$dl/z3-$ver
if [ ! -x "$z3" ] || [ "$("$z3" --version | awk '{ print $3 }')" != "$ver" ]; then
  echo "install-z3: $z3 is not Z3 $ver" >&2
  exit 1
fi

rm -rf "$Z3_BIN"
mkdir -p "$Z3_BIN"
cp "$z3" "$Z3_BIN/z3-$ver"
ln -s "z3-$ver" "$Z3_BIN/z3"

stub_names=()
for f in "$dl"/z3-*; do stub_names+=("${f##*/}"); done
IFS=: read -ra dirs <<< "$PATH"
for d in "${dirs[@]}"; do
  for f in "$d"/z3 "$d"/z3-*; do
    [ -x "$f" ] && [ ! -d "$f" ] && stub_names+=("${f##*/}")
  done
done
stubs=()
for n in "${stub_names[@]}"; do
  [ -e "$Z3_BIN/$n" ] && continue
  stubs+=("$n")
  cat > "$Z3_BIN/$n" <<EOF
#!/bin/sh
echo "olympus: '$n' is not the Z3 that F* uses; use z3 or z3-$ver" >&2
exit 127
EOF
  chmod +x "$Z3_BIN/$n"
done

msg "Z3 $ver installed in $Z3_BIN; stubs: ${stubs[*]:-none}"
