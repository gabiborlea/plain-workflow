---
name: pr-checks
description: Wait for a pull request's CI checks, then fix the failures this pull request caused, for at most 2 fix rounds. Re-runs a flaky check once, reports failures that are not this pull request's, and never merges. Use after /ship-it opens a pull request, or when the user says "watch the checks", "wait for CI", "fix the failing checks", or invokes /pr-checks.
---

# pr-checks

Load `plain-speak` first.

One job: get this pull request's checks green, or say exactly why not. It never merges,
never force-pushes, and never turns a check off.

## 1. Get the context

```bash
<this skill's base directory>/../safe-review/scripts/pr-context.sh <pr-url-or-number>
```

Use `OWNER REPO NUMBER HEAD_SHA BASE_REF SELF`. Then check the local state:

```bash
git branch --show-current            # must be the PR's head branch to push fixes
git status --porcelain               # must be empty before fix round 1
gh pr view <NUMBER> --json mergeable,headRefName,isDraft
```

| Condition | Action |
|---|---|
| `mergeable` is `CONFLICTING` | Stop. Say: `Merge conflict with <BASE_REF>. CI may not run until it is resolved.` |
| `SELF` = `other` | Watch and report only. Ask before you push any fix to another person's branch |
| The PR's head branch is not checked out here | Watch and report only. Say which branch to check out for fixes |

## 2. Wait

Run in the background, so the session gets a notice when it ends. Do not poll:

```bash
<this skill's base directory>/scripts/wait-checks.sh <OWNER>/<REPO> <NUMBER> <HEAD_SHA>
```

`<HEAD_SHA>` is the commit you expect the checks for: `HEAD_SHA` from step 1, or
`git rev-parse HEAD` right after a fix push. Until the PR head matches it, GitHub still
shows the old commit's checks.

It waits up to 5 minutes for checks to appear, and up to 60 minutes in total. Its last
line and exit code give the result:

| Exit | Last line | Action |
|---|---|---|
| 0 | `RESULT: pass` | Step 6 |
| 1 | `RESULT: fail` | Step 3 |
| 2 | `RESULT: no checks after 5 min` | Report `No CI checks on this PR.` and stop |
| 3 | `RESULT: pending after 60 min` | Report the pending checks and stop |
| 4 | `RESULT: gh error` | `gh` failed 3 times in a row. Show its error and stop. Count no round |

## 3. Read the result

For each failed check, get its log:

```bash
gh run view <run-id> -R <OWNER>/<REPO> --log-failed
```

Find the first real error, not the last line. Then sort the failure:

| Failure | How to tell | Action |
|---|---|---|
| **Caused by this PR** | The error names code, a test or a config this PR changed or depends on | Fix it in step 4 |
| **Flaky or infrastructure** | A timeout, a cancelled job, a runner or network error, or a test that this PR cannot reach | Re-run it once: `gh run rerun <run-id> --failed`. Wait again. Fails again: treat it as not this PR's |
| **Not this PR's** | The same check fails on the latest `<BASE_REF>` run: `gh run list -R <OWNER>/<REPO> --branch <BASE_REF> --workflow "<workflow>" -L 1` | Report it. Do not fix it |

A re-run is not a fix round. Each check gets max 1 re-run.

## 4. Fix, max 2 rounds

```
fix round N (N = 1, 2):
  fix the failures caused by this PR, nothing else
  run the same check locally if you can (the same test file, linter or build)
    it still fails → this round failed. Do not commit it
      N = 1 → fix round 2, starting from the uncommitted fix
      N = 2 → stop (step 5)
  commit: "<PR title prefix>: Fix <check name>"
  push (never --force)
  wait again (step 2) with the new HEAD_SHA, and read the result (step 3)
    all pass → step 6
    fails, N = 1 → fix round 2
    fails, N = 2 → stop (step 5)
```

Rules for a fix:

- **Make the code right, not the check quiet.** Never skip, delete or loosen a test.
  Never add `continue-on-error`, `--no-verify` or a retry wrapper. Never edit CI config,
  unless this PR changed that config and the change caused the failure.
- **Stay inside the PR's scope.** A fix that needs a file outside it: stop and ask.
- **The same root cause twice:** count both rounds. Do not try a third way.

## 5. Stop report

```
CHECKS FAILING after 2 fix rounds. Nothing merged.
  PR      <url>
  failing
    1. <check name> — <first real error, one line> — <caused by PR | flaky | not this PR's>
  commits pushed: <n>
  uncommitted    <files of a failed fix, or none>
```

Also use this shape, without the round count, when a stop comes from step 1, 2 or 3.

## 6. Green report

```
CHECKS GREEN  <url>
  fix rounds  <0, 1 or 2>
  re-runs     <check names, or none>
  not this PR's  <failures reported but not fixed, or none>
```

Never merge. Merging stays with the user.
