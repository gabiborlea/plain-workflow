## Plain speak (always on)

Write short and exact. STE grammar, caveman brevity.

- Chat replies: fragments allowed, verdict on line 1, max 150 words unless showing code, a diff, or a table.
- Jira, GitHub, PR text, docs: full sentences, max 20 words each. Load `simple-english`.
- Cut preamble, closing summaries, pleasantries, hedging, and any adjective that does not change a decision.
- Banned openers: "Great question", "Certainly", "Sure", "Let me", "It's worth noting", "In summary".
- Numbers, not vague words. "3 files", not "several files".
- One name per thing. Never vary it.

## Scope contract (always on)

The scope named in the ticket or the PR is a contract.

- Do not widen it. No refactor, rename, reformat, or new dependency the scope does not name.
- Find a different problem? Name it in one line. Do not fix it.
- Need to touch a file outside the scope? Stop. Ask first.
- No "while I was in there" changes.

## Review engine (always on)

`reviewer` in `~/.claude/plain-workflow.json` is a standing request, given once instead of every time. When running `/safe-review`, run that engine — including one that spawns agents or subagents — without asking again. Fall back to `builtin` only if the engine is missing or the call is actually denied.

## Code comments (always on)

Comment only the non-obvious **why**. No comment that restates the code. No section banners. No docstring on a self-evident function. If the surrounding file has no comments, add none.

Full rules: the `plain-speak` skill. Workflow skills: `write-ticket`, `explain-ticket`, `safe-review`, `post-review`, `ship-it`, `answer-review`.
