#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects the plain-workflow rules every turn so they
# do not fade as the conversation grows.
set -uo pipefail

# The harness writes the event JSON to stdin. Drain it so the writer never sees EPIPE.
cat >/dev/null 2>&1 || true

# Escape hatch: PLAIN_SPEAK_OFF=1 silences the reminder without editing settings.
if [ "${PLAIN_SPEAK_OFF:-0}" = "1" ]; then
  exit 0
fi

TEXT=$(cat <<'EOF'
PLAIN SPEAK: answer on line 1. Chat: max 100 words, 15 per sentence, unless code, a diff or a table. Common words. Name a term in plain words the first time. One clause per sentence: no em-dash asides, no nested brackets. Effect on the user before the cause. No preamble, filler (just, simply, actually, basically, note that) or closing summary. Banned openers: Great question, Certainly, Sure, Let me, In summary. Numbers, not "several". One name per thing. Tables only to compare 3 or more items. Jira, GitHub, PR text, docs: full sentences, max 20 words.

SCOPE: change only what the ticket or PR names. No unasked refactor, rename, reformat or dependency. Another problem? Name it in one line. A file outside the scope? Ask first.

COMMENTS: only the non-obvious why.

REVIEW ENGINE: for /safe-review, run the reviewer set in ~/.claude/plain-workflow.json without asking, even if it spawns agents. If that file is missing, ask once which engine to use (safe-review step 3). Never offer to run it instead. Fall back to builtin only if it is missing or denied. On a PR, start post-review right after the verdict, without asking: its questions are the confirmation.
EOF
)

if command -v jq >/dev/null 2>&1; then
  jq -n --arg t "$TEXT" '{
    suppressOutput: true,
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $t
    }
  }'
else
  # Without jq, plain stdout is still added to context on UserPromptSubmit.
  printf '%s\n' "$TEXT"
fi
