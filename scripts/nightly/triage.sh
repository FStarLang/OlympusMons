#!/usr/bin/env bash
# Usage: scripts/nightly/triage.sh
#
# After the nightly's builds: which targets failed, and can Copilot do
# anything about it? Reads the results in $OLYMPUS_WORK/status and sets, in
# $GITHUB_OUTPUT:
#
#   failed   the projects to try to fix, as a JSON matrix:
#            [{"project":"pal"},...]
#   blocked  true if F* or F*'s own CI failed, or a target left no result.
#            Nothing is recorded then, and fixing the projects would be
#            wasted effort: only F* can be fixed here, and by a human.
#   reason   why, in a sentence.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

failed=()
blocked=0
reason=''
for t in "${TARGETS[@]}"; do
  f=$OLYMPUS_WORK/status/$t
  result='no result'
  [ -f "$f" ] && read -r result _ < "$f"
  printf '%-18s %s\n' "$t" "$result"
  [ "$result" = ok ] && continue
  case $t in
    FStar|FStar-ci)
      blocked=1; reason="${reason:+$reason; }$t: $result (this is F* itself)" ;;
    *)
      if [ "$result" = 'no result' ]; then
        blocked=1; reason="${reason:+$reason; }$t left no result"
      else
        failed+=("$t")
      fi ;;
  esac
done

json=$(printf '%s\n' "${failed[@]}" | jq -R 'select(length > 0) | {project: .}' | jq -sc .)
echo
echo "to fix: $json"
[ "$blocked" = 1 ] && echo "blocked: $reason"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "failed=$json"
    echo "blocked=$([ "$blocked" = 1 ] && echo true || echo false)"
    echo "reason=$reason"
  } >> "$GITHUB_OUTPUT"
fi
exit 0
