#!/usr/bin/env bash
# Build F* (with Pulse and KaRaMeL) through stage 3 and install it as a
# binary package in _work/fstar, which all downstream projects use. Also
# snapshot the parts of the F* source tree that some projects need, so
# that they do not depend on the F* tree, where F*'s own CI may be running.
# An existing package built from the current commit is reused, unless
# CLEAN=1.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"
# The Z3 of this F* commit, for F* and every project built against it.
"$OLYMPUS_ROOT/scripts/install-z3.sh"
base_env
cd "$(src_dir FStar)"

rev=$(git rev-parse HEAD)
if [ "${CLEAN:-0}" != 1 ] \
   && [ -z "$(git status --porcelain --untracked-files=no)" ] \
   && [ "$(cat "$FSTAR_PKG/.olympus-rev" 2> /dev/null)" = "$rev" ]; then
  msg "FStar: $FSTAR_PKG is up to date"
  exit 0
fi

pmake 3
rm -f fstar.tar.gz
pmake package FSTAR_TAG= FSTAR_PACKAGE_Z3=false

rm -rf "$FSTAR_PKG" "$FSTAR_SRC"
tmp=$(mktemp -d "$OLYMPUS_WORK/fstar.XXXXXX")
tar -C "$tmp" -xzf fstar.tar.gz
mv "$tmp/fstar" "$FSTAR_PKG"
rmdir "$tmp"

# The layout of a KaRaMeL source tree, which projects expect in KRML_HOME.
mkdir "$FSTAR_PKG/karamel"
ln -s ../bin/krml "$FSTAR_PKG/karamel/krml"
ln -s ../include/krml "$FSTAR_PKG/karamel/include"
ln -s ../lib/krml "$FSTAR_PKG/karamel/krmllib"

# Pulse's makefile library (mk/) and examples (e.g. DICE, used by EverParse).
mkdir -p "$FSTAR_SRC"
git ls-files -z pulse | tar --null -T - -cf - | tar -C "$FSTAR_SRC" -xf -

"$FSTAR_PKG/bin/fstar.exe" --version
echo "$rev" > "$FSTAR_PKG/.olympus-rev"
