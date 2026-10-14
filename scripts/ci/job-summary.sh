#!/usr/bin/env bash
# Usage: scripts/ci/job-summary.sh <target>
#
# Write the result of one target to the job summary of the GitHub Actions
# job that built it: how long it took, and -- when it did not succeed -- what
# it was doing when it was killed and the end of its log, so that the common
# failures can be diagnosed from the run page without downloading anything.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/../lib.sh"

t=$1
log=$OLYMPUS_WORK/logs/$t.log
diag=$OLYMPUS_WORK/logs/$t.diagnostics.log
status=$OLYMPUS_WORK/status/$t
out=${GITHUB_STEP_SUMMARY:-/dev/stdout}

if [ -f "$status" ]; then
  read -r result rev secs < "$status"
else
  result='not run' rev='' secs=0
fi

case $result in
  ok)      icon=':white_check_mark:' ;;
  TIMEOUT) icon=':hourglass:' ;;
  FAILED)  icon=':x:' ;;
  *)       icon=':heavy_minus_sign:' ;;
esac

{
  echo "### $icon \`$t\`: $result"
  echo
  if [ -n "$rev" ]; then
    echo -n "[\`$(repo_of "${t%-ci}")@${rev:0:12}\`]"
    echo -n "(https://github.com/$(repo_of "${t%-ci}")/commit/$rev)"
    echo " &mdash; $(duration "$secs"), $JOBS parallel jobs."
  fi

  if [ "$result" = TIMEOUT ]; then
    echo
    url=${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-FStarLang/OlympusMons}
    echo "Killed after $(duration "$secs"): the limit for \`$t\` is" \
         "\`$(timeout_of "$t")\`, from \`timeout_of\` in" \
         "[\`scripts/lib.sh\`]($url/blob/${GITHUB_SHA:-main}/scripts/lib.sh)."
    if [ -s "$diag" ]; then
      echo
      echo '<details><summary>What it was doing when it was killed</summary>'
      echo
      echo '```'
      cat "$diag"
      echo '```'
      echo '</details>'
    fi
  fi

  if [ "$result" != ok ] && [ -s "$log" ]; then
    echo
    echo "<details><summary>The last 200 lines of <code>$t.log</code>" \
         "(the whole log is in the <code>log-$t</code> artifact)</summary>"
    echo
    echo '```'
    tail -n 200 "$log"
    echo '```'
    echo '</details>'
  fi
} >> "$out"
