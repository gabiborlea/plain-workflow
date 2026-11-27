---
name: post-review
description: Post a finished safe-review to GitHub. Asks which blockers and which optional findings to post (all, a selection, or none), then whether to approve or request changes, and submits one review with inline comments. Use right after /safe-review, or when the user says "post the review", "post it on the PR", or invokes /post-review.
---

# post-review

Load `plain-speak` first.

Input: the `safe-review` output in this conversation. No `safe-review` output? Say
`Run /safe-review first.` and stop.

Nothing goes to GitHub until the user answers the questions in step 2.

## Workflow

### 1. Get the context

```bash
<this skill's base directory>/../safe-review/scripts/pr-context.sh <pr-url-or-number>
```

Use `OWNER REPO NUMBER HEAD_SHA SELF`. No pull request (a working-diff review)? Say
`Nothing to post: no pull request.` and stop.

`SELF` = `self` means the user wrote the PR. GitHub then rejects approve and request
changes. Do not ask those questions. Post a comment review only, and say why in one line.

### 2. Show, then ask

Write the comments first (steps 4 and 5), then print them in chat before you ask:

```
BLOCKERS (2)
  1. src/api.ts:91  (inline)
     A 500 from S3 is caught and logged, so the caller gets 201 and the file is lost.
     Rethrow, or return 502.

OPTIONAL (1)
  1. src/util.ts:88  (review body)
     This map only checks membership. A Set is clearer.
```

The question dialog can hide the chat above it. So also put the same list, with the
exact comment text, in the `preview` of every option of that question.

Then use one `AskUserQuestion` call.

**Verdict SAFE TO MERGE:**

| Question | Options |
|---|---|
| Approve PR #N? | Approve · Do not approve |
| Post the N optional findings as comments? (only if there are any) | Post all · Pick which · Post none |

**Verdict NOT SAFE:**

| Question | Options |
|---|---|
| Post the N blockers as comments? | Post all · Pick which · Post none |
| Post the N optional findings as comments? (only if there are any) | Post all · Pick which · Post none |
| Request changes if blockers are posted? | Request changes · Comment only |

**One finding in a group:** offer `Post it · Post none`, not `Pick which`.

**Pick which:** ask again with `multiSelect: true`, one option per finding. The label is
`file:line`, the description is the exact comment text. A question holds 2 to 4 options,
so split the findings evenly: 5 → 3 + 2, 6 → 3 + 3, 7 → 4 + 3. Max 4 questions per call.

Nothing selected and no approval? Say `Nothing posted.` and stop.

### 3. Pick the review event

| Answers | Event |
|---|---|
| Approve | `APPROVE`, with any selected comments |
| At least 1 blocker posted, and Request changes | `REQUEST_CHANGES` |
| Anything else with at least 1 comment | `COMMENT` |

### 4. Write the comments

- **No label.** Never start a comment with or include "Blocking", "Blocker",
  "Optional", "Nit", "Suggestion", or a severity tag. The event carries the weight.
- Blocker: what fails and how, then the fix. Example:
  `A 500 from S3 is caught and logged, so the caller gets 201 and the file is lost. Rethrow, or return 502.`
- Optional: one sentence. Example: `` `d` does not say what it holds. `payload` is clearer. ``
- Max 20 words per sentence. No praise. No sign-off.

### 5. Anchor each comment

An inline comment must sit on a line inside a diff hunk. Get the hunks with
`gh pr diff <NUMBER> -R <OWNER>/<REPO>`. A hunk `@@ -a,b +c,d @@` covers new-file lines
`c` to `c+d-1`.

- Line inside a hunk: inline comment `{path, line, side: "RIGHT", body}`.
- Line outside every hunk: put it in the review body as `` `file:line` — text ``.

### 6. Post one review

Build the payload with `jq` in a temp file outside the repo, then send it in one call:

```bash
gh api -X POST "repos/<OWNER>/<REPO>/pulls/<NUMBER>/reviews" --input <payload.json>
```

Payload: `commit_id` = `HEAD_SHA`, `event`, `body`, `comments[]`.

`body`: the off-diff findings, one per line. If there are none: empty for `APPROVE`,
`See the inline comments.` for the other events.

A 422 that names one comment's line: move that comment to the body and retry once. Any
other error: show it and stop. Do not retry.

### 7. Report

One line: the event, the number of comments, and the review URL (`html_url` from the
response).
