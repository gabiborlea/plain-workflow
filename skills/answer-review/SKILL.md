---
name: answer-review
description: Triage pull request review comments as REAL, FALSE POSITIVE, or OUT OF SCOPE with file:line evidence for each, then fix only the approved ones and prove the fixes did not break anything. Use when the user says "address the review comments", "answer this review", "the bot left comments", "fix the review feedback", or invokes /answer-review. Skeptical by default and never fixes what nobody asked about.
---

# answer-review

Load `plain-speak` first.

Reviewers are wrong often. Bots are wrong more often. Your job is to find out which
comments are real, fix those, and prove the fixes are safe.

## Workflow

### 1. Collect every comment

Three channels. Miss one and you miss comments.

```bash
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)

# formal reviews
gh pr view <N> --repo "$REPO" --json reviews \
  --jq '.reviews[] | {author:.author.login, state, body}'

# issue comments (many bots post here, not as a review)
gh pr view <N> --repo "$REPO" --json comments \
  --jq '.comments[] | {author:.author.login, body}'

# inline review threads
gh api "repos/$REPO/pulls/<N>/comments" \
  --jq '.[] | {author:.user.login, path, line, body, id}'
```

Include `COMMENTED` reviews, not only `CHANGES_REQUESTED`.

No pull request? Take the pasted comments from the user.

### 2. Build the scope contract

Three inputs:

1. The ticket acceptance criteria. Fetch the linked ticket.
2. The pull request's stated goal, from its body.
3. The fork-point diff: `git diff $(git merge-base HEAD origin/<base>)...HEAD`

This defines OUT OF SCOPE. Without it you cannot use that verdict honestly.

### 3. Triage

One row per comment. Every row needs evidence you actually read.

```
#  who       claim                  verdict          evidence
1  copilot   null deref at L42      FALSE POSITIVE   guarded at api.ts:38
2  alice     upload error swallowed REAL             api.ts:91, catch is empty
3  copilot   rename `d` to `data`   OUT OF SCOPE     style, not in AC
4  bob       missing retry on 503   REAL             upload.ts:20, no retry
```

#### Verdict rules

| Verdict | Bar |
|---|---|
| REAL | The claim holds. You can state input → wrong result. **Default when unsure.** |
| FALSE POSITIVE | You can quote the line that disproves the claim. Highest bar of the three. |
| OUT OF SCOPE | The claim is true but sits outside the acceptance criteria and outside this diff. |

**Unsure is REAL.** Never mark FALSE POSITIVE to avoid work.

#### Proving FALSE POSITIVE

Not enough: "I checked and it is fine." "This looks safe to me."

Enough: quote the disproving line.

```
1  copilot  null deref at L42  FALSE POSITIVE  api.ts:38 `if (!user) return 400`
                                               runs before L42 on every path
```

Read the whole function, not the hunk. Check the caller. Check for an existing test.
That is where most bot findings die.

### 4. Ask which to fix

One `AskUserQuestion`. Default is all REAL items. Let the user drop any.

Do not edit a file before this answer comes back.

### 5. Fix, one item at a time

Change only what the comment asked for. No neighbouring cleanup. See the scope
contract in `plain-speak`.

If a fix needs a file outside the scope, stop and ask.

### 6. Prove each fix

Three proofs. All three. No fix reports done without them.

**Proof 1 — attacker re-read.** Read your own change as somebody trying to break it.
One line per fix:

```
#2 fix: rethrow on upload failure.
   Other callers: 2 (handler.ts:14, batch.ts:40). Both already handle a thrown
   error. No behaviour change for a successful upload.
```

Ask each time: does this break another caller? Does it change behaviour somewhere
else? Does it add a new edge case? A fix that creates a second bug is worse than the
comment.

**Proof 2 — run the tests.** Find the repo's test command. Run it. Paste the real
output.

Never write "tests should pass" or "this should work". No output, no claim.

If the tests fail, say so with the output. Do not hide it.

**Proof 3 — acceptance criteria recheck.** Once, after all fixes. Walk the original
acceptance criteria and confirm each still holds. Fixes can undo the feature.

```
AC RECHECK
  [x] Over 100 req/60s returns 429 — still passes, ratelimit.test.ts:22
  [x] Retry-After present — still passes
```

### 7. Reply on the pull request

Short replies. Full sentences, max 20 words each.

| Verdict | Reply |
|---|---|
| REAL, fixed | `Fixed in <sha>. <one line on what changed>.` |
| FALSE POSITIVE | `Not an issue. <file:line> guards this before the flagged line.` |
| OUT OF SCOPE | `True, but outside this ticket's scope. Tracked as a follow-up.` |

Reply to an inline thread:

```bash
gh api -X POST "repos/$REPO/pulls/<N>/comments/<COMMENT_ID>/replies" \
  -f body="<text>"
```

Ask before posting. Show the replies first.

### 8. Follow-up ticket for OUT OF SCOPE

Draft one through `write-ticket`. Show it. Do not create it without a yes.

Nothing gets lost. This pull request stays small.

## Hard rules

- Never change anything no comment asked about.
- Never mark FALSE POSITIVE without a quoted disproving line.
- Never claim a test passed without pasted output.
- Never fix an OUT OF SCOPE item in this pull request, even when it is small.
- Never post to GitHub before showing the user.

## Output shape

```
TRIAGE
#  who   claim  verdict  evidence
...

REAL: 2   FALSE POSITIVE: 3   OUT OF SCOPE: 1
```

Then the AskUserQuestion. Then, after fixing:

```
FIXES
#2 api.ts:91 — rethrow on upload failure
   safe: 2 callers, both handle throws already

#4 upload.ts:20 — retry 3x on 503
   safe: retry only on 503, other statuses behave as before

TESTS
<pasted output>

AC RECHECK
  [x] ...

REPLIES TO POST (not sent yet)
  #1 -> "Not an issue. api.ts:38 guards this before the flagged line."
  ...
```
