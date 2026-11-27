#!/usr/bin/env bash
# Wait for a pull request's checks with hard time caps, so a stuck check cannot hang
# the session. `gh pr checks --watch` has no timeout of its own.
#
# Usage: wait-checks.sh <OWNER/REPO> <NUMBER> [HEAD_SHA] [appear_min=5] [total_min=60]
#   HEAD_SHA: the commit just pushed. Until the PR head matches it, GitHub still shows
#   the old commit's checks, and an old failure would read as a new one.
# Exit: 0 all pass · 1 a check failed · 2 no checks appeared · 3 still pending at the cap
#       4 gh itself failed 3 times in a row (auth, rate limit, network)
set -uo pipefail

repo="$1" pr="$2" sha="${3:-}" appear_min="${4:-5}" total_min="${5:-60}"
start=$(date +%s)
elapsed_min() { echo $(( ($(date +%s) - start) / 60 )); }
errors=0

# A re-run takes a few seconds to show as pending; reading at once can see the old failure.
sleep 15

while :; do
  if [ "$(elapsed_min)" -ge "$total_min" ]; then
    gh pr checks "$pr" -R "$repo" 2>&1; echo "RESULT: pending after ${total_min} min"; exit 3
  fi

  if [ -n "$sha" ]; then
    head="$(gh pr view "$pr" -R "$repo" --json headRefOid --jq .headRefOid 2>/dev/null)"
    if [ "$head" != "$sha" ]; then sleep 15; continue; fi
  fi

  # --json exits 0 whatever the checks say, so read the buckets, not the exit code.
  out="$(gh pr checks "$pr" -R "$repo" --json bucket \
    --jq '[.[].bucket] | "\(map(select(. == "fail" or . == "cancel")) | length) \(map(select(. == "pending")) | length)"' 2>&1)"
  rc=$?

  if echo "$out" | grep -q 'no checks reported'; then
    errors=0
    if [ "$(elapsed_min)" -ge "$appear_min" ]; then echo "RESULT: no checks after ${appear_min} min"; exit 2; fi
  elif [ "$rc" -ne 0 ] || ! echo "$out" | grep -qE '^[0-9]+ [0-9]+$'; then
    errors=$((errors + 1))
    if [ "$errors" -ge 3 ]; then echo "$out"; echo "RESULT: gh error"; exit 4; fi
  else
    errors=0
    failed="${out% *}" pending="${out#* }"
    if [ "$failed" -gt 0 ]; then gh pr checks "$pr" -R "$repo" 2>&1; echo "RESULT: fail"; exit 1; fi
    if [ "$pending" -eq 0 ]; then gh pr checks "$pr" -R "$repo" 2>&1; echo "RESULT: pass"; exit 0; fi
  fi
  sleep 30
done
