#!/usr/bin/env bash
# Copied from the pr-review skill so safe-review needs nothing outside this repo.
# safe-review never posts to GitHub, so it ignores the SELF and VIEWER fields.
#
# Resolve a PR target into: OWNER REPO NUMBER HEAD_SHA BASE_REF FORK_POINT SELF VIEWER
#
# Usage: pr-context.sh <pr-url | pr-number | branch-name>
#   https://github.com/OWNER/REPO/pull/808   -> full resolve
#   808                                       -> uses the current repo's default remote
#   my-feature-branch                         -> resolves the PR opened from that branch
#
# Prints one space-separated line. FORK_POINT may be empty if the base isn't
# fetched. SELF is "self" when the authenticated gh user authored the PR
# (GitHub then rejects APPROVE/REQUEST_CHANGES — cap the verdict at COMMENT),
# else "other". VIEWER is the authenticated gh user's login — @-mention them as
# the human who will follow up; may be empty if `gh api user` fails.
set -euo pipefail

target="${1:-}"
[ -z "$target" ] && { echo "usage: pr-context.sh <pr-url|number|branch>" >&2; exit 2; }

owner="" repo="" number=""

if [[ "$target" =~ ^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  owner="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"; number="${BASH_REMATCH[3]}"
else
  # Derive owner/repo from the current checkout's origin.
  nwo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"
  [ -z "$nwo" ] && { echo "not in a gh-resolvable repo; pass a full PR URL" >&2; exit 2; }
  owner="${nwo%%/*}"; repo="${nwo##*/}"
  if [[ "$target" =~ ^[0-9]+$ ]]; then
    number="$target"
  else
    # Treat as a branch name; find its open PR.
    number="$(gh pr list --head "$target" --state all --json number --jq '.[0].number // empty' 2>/dev/null || true)"
    [ -z "$number" ] && { echo "no PR found for branch '$target'" >&2; exit 2; }
  fi
fi

# Capture the raw PR JSON, gating on gh's exit status. On a 404 (or any error)
# gh prints the error body to STDOUT and exits non-zero, so we must NOT feed
# that straight into a parser — `|| pr_json=""` both satisfies `set -e` and
# discards the error body so the friendly check below fires. `// empty` keeps a
# missing field from becoming the literal string "null".
pr_json=""
pr_json="$(gh api "repos/$owner/$repo/pulls/$number" 2>/dev/null)" || pr_json=""
head_sha="$(printf '%s' "$pr_json" | jq -r '.head.sha // empty' 2>/dev/null || true)"
base_ref="$(printf '%s' "$pr_json" | jq -r '.base.ref // empty' 2>/dev/null || true)"
author="$(printf '%s' "$pr_json" | jq -r '.user.login // empty' 2>/dev/null || true)"
[ -z "${head_sha:-}" ] && { echo "could not read PR #$number in $owner/$repo" >&2; exit 2; }

# Best-effort local fork point (needs the branches fetched locally).
fork_point=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  fork_point="$(git merge-base "origin/$base_ref" "$head_sha" 2>/dev/null || true)"
fi

# Self-review flag: GitHub's API rejects APPROVE / REQUEST_CHANGES on your own
# PR (422). Compare the PR author to the authenticated gh user so the skill can
# cap the verdict at COMMENT when they match.
viewer="$(gh api user --jq .login 2>/dev/null || true)"
self="other"
[ -n "${author:-}" ] && [ "$author" = "${viewer:-}" ] && self="self"

echo "$owner $repo $number $head_sha $base_ref $fork_point $self ${viewer:-}"
