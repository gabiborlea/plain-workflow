#!/usr/bin/env bash
# SessionStart hook. A plugin cannot edit CLAUDE.md, so this injects CLAUDE-BLOCK.md
# as session context instead.
set -uo pipefail

cat >/dev/null 2>&1 || true

BLOCK="$(dirname "${BASH_SOURCE[0]}")/../CLAUDE-BLOCK.md"
[ -f "$BLOCK" ] || exit 0

if command -v jq >/dev/null 2>&1; then
  jq -n --rawfile t "$BLOCK" '{
    suppressOutput: true,
    hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: $t }
  }'
else
  # Without jq, plain stdout is still added to context on SessionStart.
  cat "$BLOCK"
fi
