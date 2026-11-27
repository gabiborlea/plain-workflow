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
PLAIN SPEAK is active.
- Put the verdict or the answer on line 1.
- Chat reply: max 150 words, unless it shows code, a diff, or a table.
- No preamble and no closing summary. Banned openers: Great question, Certainly, Sure, Of course, Let me, It is worth noting, In summary, To recap.
- Numbers, not vague words. Write 3 files, not several files.
- One name per thing. Never vary it.
- Jira, GitHub, PR text and docs: full sentences, max 20 words each.

SCOPE CONTRACT is active.
- Change only what the ticket or the pull request names.
- No refactor, rename, reformat, or new dependency that nobody asked for.
- Found a different problem? Name it in one line. Do not fix it.
- Need a file outside the scope? Stop and ask first.

CODE COMMENTS: only the non-obvious why. None that restate the code. No section banners. If the file has no comments, add none.

REVIEW ENGINE: the reviewer value in ~/.claude/plain-workflow.json is a standing request, given once instead of every time. When running /safe-review, run that engine — including one that spawns agents or subagents — without asking again. Never offer to run it instead of running it. Fall back to builtin only if the engine is missing or the call is actually denied.
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
