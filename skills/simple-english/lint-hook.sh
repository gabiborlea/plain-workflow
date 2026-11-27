#!/usr/bin/env bash
# PostToolUse hook (Write|Edit): lint markdown docs against ASD-STE100.
# Non-blocking. Findings come back as additionalContext so Claude fixes them in-turn.
# Wired in ~/.claude/settings.json. Skill: ~/.claude/skills/simple-english/
set -uo pipefail

LINTER="$HOME/.claude/skills/simple-english/linter.py"
[ -f "$LINTER" ] || exit 0

payload=$(cat)
file=$(printf '%s' "$payload" | jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)

[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0
case "$file" in
  *.md|*.markdown) ;;
  *) exit 0 ;;
esac

# Skip scratch, throwaway, and machine-owned files. The linter grades prose meant
# for other people to read.
base=$(basename "$file")
case "$file" in
  /tmp/*|/private/tmp/*|*/scratchpad/*|*/node_modules/*|*/.git/*|*/vendor/*|*/dist/*|*/build/*) exit 0 ;;
esac
case "$base" in
  IMPLEMENTATION_PLAN.md|TODO.md|NOTES.md|CHANGELOG.md|MEMORY.md|CLAUDE.md|AGENTS.md|ONBOARDING.md) exit 0 ;;
esac

# Runbooks, procedures, and checklists get the 20-word instruction cap.
# Plain string, not an array — bash 3.2 on macOS treats an empty array as unbound under set -u.
mode=""
case "$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')" in
  *runbook*|*procedure*|*checklist*|*playbook*|*incident*) mode="--strict" ;;
esac

if [ -n "$mode" ]; then
  report=$(python3 "$LINTER" "$mode" "$file" 2>/dev/null)
else
  report=$(python3 "$LINTER" "$file" 2>/dev/null)
fi
status=$?

# Exit 0 means the file is clean. Say nothing.
[ "$status" -eq 0 ] && exit 0
[ -n "$report" ] || exit 0

jq -n --arg r "$report" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("ASD-STE100 lint findings for this file. Simplified Technical English is mandatory for technical documentation — see the simple-english skill. Fix these before you finish the turn. The linter cannot tell use from mention, so ignore hits on text that quotes a banned word to define it.\n" + $r)
  },
  suppressOutput: true
}'
exit 0
