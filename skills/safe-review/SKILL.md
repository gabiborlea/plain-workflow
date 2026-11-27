---
name: safe-review
description: Answer one question about a pull request — is it safe to merge to main? Runs the configured review engine, then keeps only findings that were introduced by this diff AND break the feature or endanger main. Everything else is dropped to a short optional list. Use when the user says "is this safe to merge", "review this PR", "can I merge", or invokes /safe-review.
---

# safe-review

Load `plain-speak` first.

One question: **is this pull request safe for main?** Not "is it perfect". Not "could
it be nicer". Safe.

## Workflow

### 1. Get the context and the real fork point

```bash
~/.claude/skills/safe-review/scripts/pr-context.sh <pr-url-or-number>
```

Prints `OWNER REPO NUMBER HEAD_SHA BASE_REF FORK_POINT SELF VIEWER`. Ignore `SELF`
and `VIEWER`. This skill never posts.

If `FORK_POINT` is empty, run `git fetch origin <BASE_REF>` and the branch, then re-run.
**Do not continue without a fork point.** Gate 1 depends on it. Without it every
pre-existing problem looks introduced, and the noise comes straight back.

No pull request? Use the working diff:
`git diff $(git merge-base HEAD origin/<base>)...HEAD`

### 2. Get the acceptance criteria

In order of preference:

1. The linked ticket. Fetch it, use its acceptance criteria.
2. The pull request body.
3. Ask the user in one line: `No acceptance criteria found. What must this PR do?`

Without acceptance criteria, Gate 2 cannot test "breaks the feature". Do not skip this.

### 3. Run the configured engine

Read `~/.claude/plain-workflow.json` and take `.reviewer`. A missing file means `auto`.

| Value | What to run |
|---|---|
| `auto` | The first of these that exists: `pr-review-toolkit:review-pr`, then `code-review`, then `builtin` |
| `pr-review-toolkit:review-pr` | The full multi-agent sweep |
| `code-review` | The `code-review` skill, one pass |
| `builtin` | No external engine. Use the pass below. |
| anything else | Treat it as the name of a skill, agent, or slash command and invoke it |

**The `reviewer` value is a standing request. Run it. Do not ask.**

The user wrote it into a config file on purpose, so running that engine is the requested
action, not something extra you decided to do. This holds even when a general rule in
the session says not to spawn agents, run subagents, or start a workflow unless the user
asks — the config **is** the ask, given once instead of every time.

Do not offer to run it. Do not say "say the word and I will run the full sweep". Do not
downgrade to `builtin` because the engine spawns agents. Downgrade only for the one
reason below.

The only exception is a genuine tool denial. If the harness blocks or the user rejects
the call, say so in one line, then fall back to `builtin`.

**Confirm the engine exists before you run it.** A plugin skill exists only when its
plugin is enabled in `~/.claude/settings.json`. If the configured engine is absent, say
one line and continue:

```
Configured reviewer <name> not found. Falling back to builtin.
```

Never stop over a missing engine. The user still gets a verdict.

#### The builtin pass

No fan-out. Read the fork-point diff and hunt **only** the Gate 2 categories:

- An acceptance criterion that the diff fails to meet.
- Security hole, missing authorization, leaked secret.
- Data loss or corruption.
- Crash on a reachable path.
- Silent error swallow that loses data.
- Broken existing behaviour.
- A repo-mandated rule the diff breaks (raw SQL where a query builder is required).
- A migration out of sequence with the base branch.

Read each changed file whole, not the hunk alone. Follow the callers of every changed
function. Skip everything the list does not name.

Whatever the engine, its output still passes through the three gates in step 4. The
engine is swappable. The filter is not.

### 4. Filter

Every finding passes through three gates. Full rules and worked cases:
[GATES.md](GATES.md)

| Gate | Test | Fail means |
|---|---|---|
| 1 Introduced | The finding sits on a line this diff added or changed, measured from `FORK_POINT`. | Drop to optional. Pre-existing never blocks. |
| 2 Blocking | It breaks an acceptance criterion or the happy path, **or** it is unsafe for main. | Drop to optional. |
| 3 Verified | You have a `file:line` and can state the concrete failure: input, then wrong result. | Drop entirely. Unverified findings are noise. |

**Unsafe for main** means exactly one of:

- Security hole. Injection, auth bypass, missing authorization check.
- Leaked secret. Key, token, or password in code, config, or logs.
- Data loss or corruption.
- Crash or unhandled exception on a reachable path.
- Silent error swallow that loses data or hides a failure.
- Breaks existing behaviour that other code or users depend on.
- Breaks a rule that the repo's `CLAUDE.md` calls mandatory or review-blocking. Example:
  a new raw SQL string where the repo requires its query builder.
- Migration out of sequence, where the repo orders migrations by a number or timestamp
  prefix. A new migration file uses a prefix that the base branch already has, or one
  that sorts before the newest file on the base branch. Compare against a fresh
  `git fetch origin <BASE_REF>`, not the fork point. Many migration tools refuse
  out-of-order files at deploy; report it so the author fixes it first.

Nothing else is blocking. Not naming. Not structure. Not test coverage. Not
duplication. Not a missing type. Not a comment.

### 5. Output

```
VERDICT: SAFE TO MERGE
```

or

```
VERDICT: NOT SAFE

BLOCKERS (2)
  1. src/api.ts:91 — upload failure is swallowed — a 500 from S3 is caught and
     logged, the caller gets 201, the file is gone
     fix: rethrow, or return 502

  2. src/auth.ts:24 — token expiry uses < not <= — a token expiring this exact
     second is accepted
     fix: change < to <=

AC CHECK
  [x] Over 100 req/60s returns 429 — verified, ratelimit.ts:40
  [ ] Retry-After header present — not set, ratelimit.ts:47

OPTIONAL (5, not blocking)
  - src/api.ts:12 — `d` is a poor name for the payload
  - src/util.ts:88 — this map could be a Set
  - src/auth.ts:60 — no test for the expiry boundary
  - src/api.ts:30 — duplicated with handler.ts:14
  - src/config.ts:5 — magic number 100, could be named
```

Rules for the output:

- Verdict on line 1. Always.
- One blocker per numbered item. Two lines: what and how it fails, then the fix.
- `AC CHECK` lists every acceptance criterion with evidence or a gap.
- `OPTIONAL` is **max 5 items, one line each**. More than 5 exist? Show the 5 that
  matter most and add `+N more dropped`.
- No other sections. No summary paragraph. No praise.

Name the engine in the first line of the output when it was not `auto`'s top choice,
so the user knows what produced the findings:

```
VERDICT: NOT SAFE   (engine: builtin)
```

### 6. Do not post

Output goes to chat. This skill never comments on GitHub.

The user has `pr-review` for posting. Say so in one line if they want it on the PR.

### 7. Remove the review worktrees

When the review of a pull request is done, remove every worktree that this review
created for it, yours or a subagent's. Do not wait for the user to ask.

1. Check that `git -C <worktree> status --short` is empty. If it is not, stop and ask.
2. Run `git worktree remove -f -f <worktree>`. A subagent worktree is locked, so one `-f`
   is not enough.
3. Delete its branch: `git branch -D worktree-<name>`, if the branch exists.

Run the removal in the background. A worktree with `node_modules` takes minutes to delete.
Never remove a worktree that this review did not create.

## When you are unsure

A finding you cannot verify is not a finding. Drop it.

A finding that might be blocking but you cannot prove the failure: state it as a
blocker only if the risk is security or data loss. Otherwise it goes to optional.
