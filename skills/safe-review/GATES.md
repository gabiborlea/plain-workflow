# The three gates

Every finding from the sweep runs this in order. Stop at the first fail.

```
finding
   │
   ├─ Gate 1: on a line this diff added or changed? ──── no ──▶ OPTIONAL
   │                                                              (pre-existing)
   ├─ Gate 2: breaks the feature, or unsafe for main? ── no ──▶ OPTIONAL
   │                                                              (nit)
   ├─ Gate 3: file:line + concrete failure? ──────────── no ──▶ DROP
   │                                                              (unverified)
   ▼
BLOCKER
```

## Gate 1 — Introduced

**Test:** the finding's line appears in `git diff FORK_POINT...HEAD`.

Run it. Do not judge by eye.

```bash
git diff --unified=0 "$FORK_POINT...HEAD" -- <file> | grep -n '^+'
```

### Cases

| Case | Gate 1 |
|---|---|
| The diff adds line 91 and the bug is on line 91 | Pass |
| The diff changes a function, the bug is in an untouched line of it | Fail |
| The diff calls an existing broken function for the first time | Pass — the diff made it reachable |
| The bug existed and the diff moved the line | Fail — moving is not introducing |
| The diff deletes a guard that used to prevent the bug | Pass |

### Why this gate exists

Pre-existing problems in touched files are the largest source of review noise. They are
real, and they are somebody's work, but they are not this pull request's job. Fixing
them here grows the diff and restarts the review.

A pre-existing problem that is severe belongs in a follow-up ticket, not in this pull
request.

## Gate 2 — Blocking

Two ways to pass. Either one is enough.

### 2a — Breaks the feature

The finding means a stated acceptance criterion is not met, or the happy path does not
work.

Test it against the acceptance criteria you collected in step 2. Name the criterion.

- Pass: `AC "returns 429 over the limit" — the counter resets on every request, so it
  never returns 429.`
- Fail: `the retry count is 3 and the ticket does not say how many retries.`

### 2b — Unsafe for main

Exactly one of these. The list is closed. Only the user extends it.

| Category | Example |
|---|---|
| Security hole | SQL built by string concatenation from a request field |
| Missing authorization | A route that reads another tenant's data with no check |
| Leaked secret | An API key committed, or a token written to a log line |
| Data loss or corruption | A migration that drops a column with no backup |
| Crash on a reachable path | `user.name` where `user` can be null from the API |
| Silent error swallow | `catch (e) {}` around a write that can fail |
| Breaks existing behaviour | A response field renamed while clients still read the old name |
| Breaks a mandatory repo rule | A new raw SQL string where the repo's `CLAUDE.md` requires its query builder |
| Migration out of sequence | The PR adds migration `0005_*`, but the base branch already has `0005_*` or `0006_*` |

**Mandatory repo rule:** only a rule that the repo's `CLAUDE.md` states as mandatory,
review-blocking, or "never". A style preference in `CLAUDE.md` is still optional. Quote
the rule in the finding.

**Migration sequence:** applies only when the repo orders migrations by a number or
timestamp prefix. Run `git fetch origin <BASE_REF>`, then list the migration directory
on `origin/<BASE_REF>`. The PR's migration must sort after every file there. If the repo
numbers migrations without gaps, the PR's number must also leave no gap. Gate 1 passes,
because the PR adds the file, even when the collision comes from new commits on the
base branch.

### Not blocking — always optional

Naming · formatting · structure · duplication · a missing test · a missing type ·
a comment · a magic number · an unused import · a preference about a library ·
"this could be simpler" · "this is not how we usually do it" · performance with no
measured problem.

These are real observations. They are not merge gates. Showing them is what turns a
review into a loop.

## Gate 3 — Verified

You must be able to write this sentence:

> With input **X**, line **file:N** produces **Y**, and the correct result is **Z**.

If you cannot fill all four slots, the finding is not verified.

### Verify by reading, not by guessing

- Open the file. Read the function, not the diff hunk alone.
- Follow the caller. Is the bad input reachable?
- Check for a guard earlier in the path. Many findings die here.
- Check whether a test already covers it.

### Cases

| Claim | Verified? |
|---|---|
| "`user.id` may be null" — and the caller checks `if (!user) return` on the line above | No. Drop. |
| "`user.id` may be null" — and the API type marks `user` optional, no guard, route is public | Yes |
| "This might have a race condition" | No. No input, no concrete result. Drop. |
| "Two requests within 10 ms both pass the check at line 40 and both write, so the second overwrites the first" | Yes |

## Counting the optional list

Cap at 5. Rank by:

1. Would it cause a bug later? (highest)
2. Does it make the code hard to change?
3. Is it a style preference? (lowest — usually cut)

More than 5 survive? Show 5 and write `+N more dropped`. Never expand the list because
the findings are good. The cap is the feature.
