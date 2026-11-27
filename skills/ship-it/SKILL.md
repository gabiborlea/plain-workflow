---
name: ship-it
description: Ship the current uncommitted changes end to end — draft and create a ticket, cut a branch, commit, run safe-review on the branch, fix blockers for at most 2 rounds, then push, open the pull request and run pr-checks on it. Stops before the pull request if the branch is still not safe. Use when the user says "ship this", "ship it", "turn this into a ticket and PR", or invokes /ship-it.
---

# ship-it

Load `plain-speak` first. Load `write-ticket` for steps 1 and 2. Load `safe-review` for
step 5. Load `pr-checks` for step 7.

Take the uncommitted changes. Turn them into a ticket, a branch, a commit, a safe
review, a push and a pull request, in that order. No pull request opens while
`safe-review` says NOT SAFE.

## Preflight

Find the base branch first. `<base>` is the bare name, such as `main`:

```bash
gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
# no gh repo: git remote show origin | sed -n 's/.*HEAD branch: //p'
```

Then run these read-only commands in parallel:

```bash
git status --porcelain
git branch --show-current
git fetch origin <base>
git ls-files --others --exclude-standard
```

Stop before you create anything:

| Condition | Say |
|---|---|
| `git status` is empty | `Nothing to ship.` |
| The repo's `CLAUDE.md` forbids new branches in this checkout | Quote the rule, then ask how to continue |
| The current branch is not the base branch | Ask: continue on this branch, or stash and branch from the base? |

## 1. Draft the ticket

Run `write-ticket` steps 1 to 4: detect the tracker, draft at once, ask the gaps in one
round, finalise. The input is the diff: `git diff origin/<base>...HEAD`, `git diff`, and
the content of the untracked files.

Also pick:

- **Title:** imperative mood, max 70 characters, no trailing period.
- **Type:** `Task` by default, `Bug` for a fix, `Story` for a new feature. Jira only.

Show the title, the type and the full body. Wait for a yes or edits.

## 2. Create the ticket

Run `write-ticket` step 5 with the approved draft.

- **Jira through the Atlassian MCP:** assign the ticket to the current user in the
  create call. Then move it to "In Progress": list the transitions and pick the one
  whose target status is "In Progress". If none exists, or the move fails, continue and
  say so in the final report.
- **GitHub:** `gh issue create`.

Keep the key: `ENG-42` for Jira, `#42` for GitHub. If creation fails after one retry,
stop. Create no branch and no commit.

## 3. Cut the branch

Slug: lowercase the title, replace each non-alphanumeric run with `-`, trim the ends,
cap at 40 characters.

| Tracker | Branch |
|---|---|
| Jira | `ENG-42-<slug>` |
| GitHub | `42-<slug>` |

If the name exists locally or on the remote, append `-2`, `-3` and so on.

- From the base branch: `git checkout -b <branch>`.
- From another branch, user chose "branch from the base": `git stash -u`,
  `git checkout <base> && git pull --ff-only`, `git checkout -b <branch>`, `git stash pop`.
- From another branch, user chose "continue": `git checkout -b <branch>`.

## 4. Commit

Stage named paths from `git status`. Never `git add -A` or `git add .`. Skip `.env*`,
`*credentials*` and large binaries. Ask before you commit anything that looks secret.

Message: `<KEY>: <title>`, then the ticket's Problem section as the body. Follow the
repo's recent `git log` style and the user's `CLAUDE.md` rules for commit trailers.

## 5. Safe review, max 2 fix rounds

Run `safe-review` on the branch, with no pull request. The review range is
`$(git merge-base HEAD origin/<base>)...HEAD`. Give it the ticket's acceptance criteria,
so it does not ask for them. Do not hand off to `post-review`: there is no pull request
yet.

**Give the range to the review engine by name.** The work is committed and no pull
request exists, so an engine that scopes by `git diff` or `gh pr view` sees nothing. It
then returns 0 findings, and an unreviewed branch passes as SAFE TO MERGE.

```
round 0: review
  SAFE TO MERGE → step 6
  NOT SAFE      → fix round 1

fix round N (N = 1, 2):
  fix each blocker, nothing else
  run the tests that cover the changed files
    a test fails → this round is NOT SAFE, skip its review
      N = 1 → fix round 2, starting from the uncommitted fix
      N = 2 → stop
  commit: "<KEY>: Fix <short blocker name>"
  review again
    SAFE TO MERGE → step 6
    NOT SAFE, N = 1 → fix round 2
    NOT SAFE, N = 2 → stop
```

Rules for a fix round:

- **Fix blockers only.** Optional findings stay as they are. The scope contract holds.
- **A fix that needs a file outside the ticket's scope:** stop and ask.
- **A failing test after a fix:** the round is NOT SAFE, whatever a review would say. A
  red test never reaches step 6. Do not commit the failed fix. The next round starts
  from it, or the stop report names it.

**Stop after fix round 2.** Do not push. Do not open a pull request. Report:

```
NOT SAFE after 2 fix rounds. No pull request opened.
  ticket  ENG-42
  branch  ENG-42-<slug> (local, not pushed)
  uncommitted  <files of a failed fix, if any>
  blockers left:
    1. <file:line> — <what fails>
```

## 6. Push and open the pull request

```bash
git push -u origin <branch>
gh pr create --title "<KEY>: <title>" --body-file <file>
```

Build the body from the ticket. No new drafting:

```
## Summary

Closes <ticket link or #42>.

- <each Scope "In" bullet>

## Safe review

SAFE TO MERGE after <0, 1 or 2> fix rounds.

## Test plan

- [ ] <each acceptance criterion and test plan step>
```

Full sentences, max 20 words each. Print the pull request URL.

## 7. Watch the checks

Run `pr-checks` on the new pull request. Do not ask first: waiting for CI is part of
shipping. Its fix rounds are its own, max 2, separate from the 2 in step 5.

## Report

```
SHIPPED  <PR URL>
  ticket   ENG-42 (In Progress)
  branch   ENG-42-<slug>
  review   SAFE TO MERGE, 1 fix round
  checks   GREEN, 0 fix rounds   (or the pr-checks stop report)
  optional 3 findings not fixed (listed in the review above)
```
