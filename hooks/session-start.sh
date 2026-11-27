#!/usr/bin/env bash
# SessionStart hook. A plugin cannot edit CLAUDE.md, so this injects CLAUDE-BLOCK.md
# as session context instead. It also flags a leftover install.sh setup, which would
# load the rules and the reminder hook a second time.
set -uo pipefail

cat >/dev/null 2>&1 || true

BLOCK="$(dirname "${BASH_SOURCE[0]}")/../CLAUDE-BLOCK.md"
[ -f "$BLOCK" ] || exit 0

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

found=()
grep -qF '<!-- BEGIN plain-workflow -->' "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null && found+=("the block in CLAUDE.md")
grep -qF 'plain-speak-reminder' "$CLAUDE_DIR/settings.json" 2>/dev/null && found+=("the reminder hook in settings.json")

clone=""
for name in plain-speak safe-review post-review write-ticket explain-ticket answer-review simple-english; do
  link="$CLAUDE_DIR/skills/$name"
  if [ -L "$link" ]; then
    found+=("the skill link skills/$name")
    target="$(readlink "$link")"
    [ -z "$clone" ] && clone="${target%/skills/*}"
  fi
done

TEXT="$(cat "$BLOCK")"
NOTICE=""
if [ "${#found[@]}" -gt 0 ]; then
  where="${clone:-<your plain-workflow clone>}"
  list="$(printf '%s, ' "${found[@]}")"
  NOTICE="plain-workflow: an old install.sh setup is still present (${list%, }). Run ${where}/uninstall.sh, or the rules load twice."
  TEXT="$TEXT

## Old plain-workflow install found

$NOTICE
At the start of your first reply, tell the user this in one line. Offer to run the uninstall for them, with --dry-run first."
fi

if command -v jq >/dev/null 2>&1; then
  jq -n --arg t "$TEXT" --arg n "$NOTICE" '{
    suppressOutput: true,
    hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: $t }
  } + (if $n == "" then {} else { systemMessage: $n } end)'
else
  # Without jq, plain stdout is still added to context on SessionStart.
  printf '%s\n' "$TEXT"
fi
