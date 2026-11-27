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
<this skill's base directory>/scripts/pr-context.sh <pr-url-or-number>
```

Prints `OWNER REPO NUMBER HEAD_SHA BASE_REF FORK_POINT SELF VIEWER`. Ignore `SELF`
and `VIEWER`. This skill never posts.

If `FORK_POINT` is empty, run `git fetch origin <BASE_REF>` and the branch, then re-run.
**Do not continue without a fork point.** Gate 1 depends on it. Without it every
pre-existing problem looks introduced, and the noise comes straight back.

No pull request? Use the working diff:
`git diff $(git merge-base HEAD origin/<base>)...HEAD`. Then `FORK_POINT` is that
merge-base and `HEAD_SHA` is `HEAD`.

### 2. Get the acceptance criteria

In order of preference:

1. The linked ticket. Fetch it, use its acceptance criteria.
2. The pull request body.
3. Ask the user in one line: `No acceptance criteria found. What must this PR do?`

Without acceptance criteria, Gate 2 cannot test "breaks the feature". Do not skip this.

### 2b. Collect the repo's gating rules

The repo's own rules can block a merge. Read them from the files, not from memory.

1. List the rule files that govern the diff: the root `CLAUDE.md` and `AGENTS.md`, and
   each `CLAUDE.md` or `AGENTS.md` in a changed file's own folder or a parent folder.
   Read them at the PR head, not from the local checkout.

   ```bash
   git diff --name-only <FORK_POINT>...<HEAD_SHA>
   git ls-tree -r --name-only <HEAD_SHA> | grep -E '(^|/)(CLAUDE|AGENTS)\.md$'
   git show <HEAD_SHA>:<rule file>
   ```

2. From those files, keep only the **gating rules**: a rule stated with `must`, `never`,
   `mandatory`, `required`, `review-blocking`, or one that says CI fails or blocks.
   A preference ("prefer", "try to", "usually") is not a gate.
3. Keep only the gates that the diff touches: its paths, file types, APIs, or PR body.
4. Note each gate with its `file:line`. Step 4 checks each one, and step 5 lists them.

No gate applies? Say `RULES CHECK: no gating rule applies` in the output.

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
- Breaks a gating rule from step 2b. Quote the rule and its `file:line`. Example: a new
  raw SQL string where the repo's `CLAUDE.md` requires its query builder.
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

BLOCKERS (3)
  1. src/api.ts:91
     The caller gets 201, but the file is lost. Cause: a 500 from S3 is caught and logged.
     Fix: rethrow, or return 502.

  2. src/auth.ts:24
     A token that expires this exact second is accepted. Cause: the check uses < not <=.
     Fix: change < to <=.

  3. src/api.ts:120
     Any user can read another tenant's exports. Cause: the new route skips the tenant
     check that api/CLAUDE.md:8 requires: "Every route must check the tenant."
     Fix: call requireTenant() first, as the other routes do.

AC CHECK
  [x] Over 100 requests in 60 s returns 429. Proof: ratelimit.ts:40.
  [ ] Retry-After header present. Gap: not set, ratelimit.ts:47.

RULES CHECK
  [x] CLAUDE.md:42 "New queries must use the query builder." Proof: no raw SQL added.
  [ ] api/CLAUDE.md:8 "Every route must check the tenant." Gap: blocker 3.

OPTIONAL (5, not blocking)
  - src/api.ts:12: `d` does not say what it holds.
  - src/util.ts:88: this map only checks membership. A Set is clearer.
  - src/auth.ts:60: no test covers the expiry boundary.
  - src/api.ts:30: repeats handler.ts:14.
  - src/config.ts:5: the limit 100 has no name.
```

Rules for the output:

- Verdict on line 1. Always.
- One blocker per numbered item. Three lines: `file:line`, then the effect and the
  cause, then the fix.
- `AC CHECK` lists every acceptance criterion with proof or a gap.
- `RULES CHECK` lists every gating rule from step 2b, quoted, with proof or a gap. A
  gap from a break this diff introduced is a blocker of its own, which quotes the rule.
  Gate 1 still applies: a break that was already there is a gap with `pre-existing`,
  not a blocker.
- `OPTIONAL` is **max 5 items, one line each**. More than 5 exist? Show the 5 that
  matter most and add `+N more dropped`.
- No other sections. No summary paragraph. No praise. Plain-speak rules apply.

Name the engine in the first line of the output when it was not `auto`'s top choice,
so the user knows what produced the findings:

```
VERDICT: NOT SAFE   (engine: builtin)
```

### 6. Hand off to post-review

Output goes to chat. This skill never comments on GitHub.

For a pull request, load `post-review` next and follow it. It asks the user what to post.

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
