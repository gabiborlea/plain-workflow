# plain-workflow — design

Date: 2026-08-07
Status: approved

## Problem

Claude output is too long and too complex to read fast. Pull request scope drifts away
from the ticket. Code review loops do not end. Code carries comments that add no
information. The user loses time on all four.

## Goal

Six skills that make Claude short, exact, and inside scope. Four do work. One holds
the shared rules. One, `simple-english`, is vendored because the others depend on it.

## Voice — how the conflict is resolved

Caveman and STE pull opposite ways. Caveman drops articles and uses fragments. STE
demands full sentences, articles, and active voice. The blend is **STE grammar,
caveman brevity**, split by audience.

| Audience | Register |
|---|---|
| Chat to the user | Fragments allowed. Verdict first. Max 150 words unless the reply shows code, a diff, or a table. |
| Jira, GitHub, PR text, docs | Full sentences. Other humans read them. Max 20 words per sentence. STE-flavored, per the existing `simple-english` skill. |

Both registers share these cuts:

- No preamble. No "let me", "I'll now", "first I will".
- No closing summary of what was just said.
- No pleasantries and no hedging.
- No adjective that does not change a decision.
- Numbers, not vague words. "3 files", not "several files".
- One idea per sentence.
- One name per thing. Never vary it.
- Bullets nest one level deep at most.

## Scope contract — the anti-drift rule

- The scope named in the ticket or the pull request is a contract. Do not widen it.
- Find a different problem? Name it in one line. Do not fix it.
- No refactor, rename, reformat, or new dependency that the scope does not name.
- Need to change a file outside the scope? Stop. Ask first.

## Code comments

Comment only the non-obvious *why*. Do not restate what the code does. No section
banners. No docstring on a self-evident function. A reader who asks "why is it done
this strange way" is the only reader a comment serves.

## The five new skills

### plain-speak

Shared core. No slash command. The other four load it.

Holds the voice table, the shared cuts, the scope contract, the code-comment rule, and
a self-check list to run before any reply is sent.

A condensed copy (about 15 lines) lives in `~/.claude/CLAUDE.md` so the rules apply
without a skill load. This mirrors how `simple-english` already works.

A `UserPromptSubmit` hook re-injects the same rules on every prompt. The `CLAUDE.md`
block is read once at session start, so it fades as the conversation grows. The hook
does not. It returns the rules as `additionalContext` with `suppressOutput`, so the
user sees nothing. `PLAIN_SPEAK_OFF=1` silences it.

### /write-ticket

Drafts a ticket. Does not create it without approval.

1. Detect the tracker. Read `jira_host` and `jira_keys` from
   `~/.claude/plain-workflow.json`. A key whose prefix is in `jira_keys` means Jira. A
   GitHub remote and no Jira key means GitHub. If neither is clear, ask once. Never
   guess a Jira host.
2. Draft at once from whatever the user gave. Mark each hole `? NEEDS ANSWER`.
3. Ask all holes in one `AskUserQuestion` round.
4. Produce the final draft. Run the `simple-english` lint pass on it.
5. Ask whether to create the ticket. Never create it without a yes.

Template:

```
Problem       1 to 3 sentences. Why now.
Scope
  In          testable bullets
  Out         "Not in this ticket:" — an explicit list
Acceptance    - [ ] observable checkboxes, no implementation detail
Test plan     how a human verifies by hand
Diagram       when flow or state is involved
              ASCII in a code block for Jira, Mermaid for GitHub
```

Size gate: more than 5 in-scope bullets, or more than 7 acceptance boxes, means the
ticket is too big. Say so and propose the split.

### /explain-ticket

Reads a ticket and makes it clear. Fetches by key, by URL, or from pasted text.

Fixed output shape, about 120 words:

```
WHAT        one sentence
WHY         one sentence
DONE WHEN   the acceptance criteria as checkboxes, reworded plain
NOT IN IT   out of scope, or "not stated"
UNCLEAR     open questions, or "none"
```

Hard rule: do not read the code, do not name files, do not propose an approach. If the
ticket has no acceptance criteria, say so and offer `/write-ticket`.

### /safe-review

Answers one question: is this pull request safe for main?

1. Get pull request context and the real fork point with
   `skills/safe-review/scripts/pr-context.sh`, copied from the `pr-review` skill so
   nothing outside this repository is required. Ignore its `SELF` and `VIEWER`
   fields; this skill never posts.
2. Get the acceptance criteria from the linked ticket. If none, use the pull request
   body. If still none, ask.
3. Run the configured engine. Read `.reviewer` from `~/.claude/plain-workflow.json`.
   A missing file means `auto`. `auto` resolves to the first present of
   `pr-review-toolkit:review-pr`, `code-review`, `builtin`. Any other value names a
   skill, agent, or slash command to invoke. A missing engine produces one warning
   line and falls back to `builtin`; it never stops the review.
   `builtin` is a single narrow pass over the fork-point diff that hunts only the
   Gate 2 categories, with no fan-out.
4. Put every finding through three gates. A finding that fails any gate drops to the
   optional list.
   - Gate 1 — Introduced. The finding is in the diff against the fork point.
     Pre-existing problems never block.
   - Gate 2 — Blocking. The finding breaks an acceptance criterion or the happy path,
     or it is unsafe for main: security hole, data loss, crash, silent error swallow
     that loses data, broken existing behaviour, or a leaked secret.
   - Gate 3 — Verified. A `file:line` and a concrete failure description exist.
5. Output:

```
VERDICT: SAFE TO MERGE  |  NOT SAFE

BLOCKERS (n)
  1. file:line — what breaks — how it fails
     fix: one line

AC CHECK
  [x] AC1 — met, evidence
  [ ] AC2 — not met

OPTIONAL (max 5, not blocking)
  - one line each
```

Output goes to chat only. The existing `pr-review` skill posts to GitHub.

The engine is swappable. The filter is not. The multi-agent sweep is slow and most of
its output is discarded, which is why it is a choice and not a requirement.

### /answer-review

Triages review comments, then fixes the ones the user approves.

1. Collect comments from all three channels: formal reviews, issue comments, and review
   threads. The `gh` calls are written out in the skill, so no other skill is needed.
2. Build the scope contract from the ticket acceptance criteria, the pull request goal,
   and the fork-point diff.
3. Triage. One row per comment.

```
#  who    claim            verdict          evidence
1  bot    null deref L42   FALSE POSITIVE   guarded at L38
2  human  missing retry    REAL             api.ts:91, no catch
3  bot    rename this      OUT OF SCOPE     not in the acceptance criteria
```

   Every verdict needs a `file:line` that was actually read. FALSE POSITIVE needs the
   strongest evidence: quote the line that disproves the claim. When unsure, the
   verdict is REAL.
4. Ask which REAL items to fix. Default is all of them.
5. Fix each approved item. Then show three proofs:
   - Attacker re-read. One line: what else this could break, and why it does not.
   - Test output. Real, pasted. Never claim a pass without output.
   - Acceptance criteria recheck, once, after all fixes.
6. Reply on the pull request. FALSE POSITIVE gets a short reply with the evidence.
   OUT OF SCOPE gets a short reply plus a follow-up ticket drafted through
   `/write-ticket`. Show the draft. Do not create it without a yes.
7. Never change anything that no comment asked about.

## Packaging

Git repository, cloned anywhere. `install.sh` resolves its own path. Local only. No
remote for now.

```
plain-workflow/
  README.md
  install.sh
  uninstall.sh
  CLAUDE-BLOCK.md
  hooks/plain-speak-reminder.sh
  config.example.json
  skills/safe-review/scripts/pr-context.sh
  docs/specs/2026-08-07-plain-workflow-design.md
  skills/
    plain-speak/SKILL.md
    write-ticket/SKILL.md
    write-ticket/TEMPLATE.md
    explain-ticket/SKILL.md
    safe-review/SKILL.md
    safe-review/GATES.md
    answer-review/SKILL.md
    simple-english/            vendored, not authored here
```

`simple-english` is vendored because `plain-speak` and `write-ticket` both load it, and it
existed on one machine only, tracked by nothing. `caveman` is not vendored: nothing
loads it, and its rules contradict STE.

### Configuration

Everything org-specific lives in `~/.claude/plain-workflow.json`, outside the
repository, so a `git pull` never conflicts with it.

| Key | Effect | Default |
|---|---|---|
| `reviewer` | The engine `safe-review` runs | `auto` |
| `jira_host` | Jira host. Empty means GitHub only. | empty |
| `jira_keys` | Project prefix to STE mode. Presence identifies a Jira ticket; the value is `strict` or `flavored`. | empty |

`jira_keys` is one map, not two lists. An earlier draft had `jira.keys` and
`ste.strict_keys` naming the same projects twice, so a project could be listed in one
and forgotten in the other.

Every default is empty. A fresh clone assumes nothing about the user's organisation.
No repository file holds a host name, a project key, or a user name.

### Runtime requirements

`install.sh` reports each one and continues. A missing tool is a warning.

| Tool | Needed by |
|---|---|
| `jq` | `install.sh`, the reminder hook |
| `git` | `safe-review` fork point |
| `gh`, authenticated | `explain-ticket`, `safe-review`, `answer-review` |
| `python3` | the `simple-english` linter |

No skill or plugin outside this repository is required.

### install.sh contract

- Runs under `bash` with `set -euo pipefail`.
- Finds the repository root from `${BASH_SOURCE[0]}`. Works from any directory.
- Target directory is `${CLAUDE_DIR:-$HOME/.claude}/skills`.
- For each directory under `skills/`, create a symlink at `<target>/<name>`.
  - Symlink already points at the same path: report `ok`, change nothing.
  - Symlink points somewhere else: replace it, report `relinked`.
  - A real directory or file is in the way: move it to
    `${CLAUDE_DIR}/.plain-workflow-backups/<name>.<timestamp>`, then link. Report
    `backup`. The backup must not stay inside `skills/`: Claude Code scans every
    directory there and would register the backup as a duplicate skill.
- Inject `CLAUDE-BLOCK.md` into `${CLAUDE_DIR:-$HOME/.claude}/CLAUDE.md` between
  `<!-- BEGIN plain-workflow -->` and `<!-- END plain-workflow -->`.
  - Markers present: replace the text between them.
  - Markers absent: append the block with markers.
  - Copy `CLAUDE.md` to `CLAUDE.md.bak.<timestamp>` before any edit.
- Add the `UserPromptSubmit` hook to `${CLAUDE_DIR:-$HOME/.claude}/settings.json`.
  - Needs `jq`. Without it, report `skip` and continue with the other steps.
  - A malformed `settings.json` is reported and left untouched.
  - Identify the entry by the `plain-speak-reminder` tag in its command. Strip any
    tagged entry before appending, so a changed repository path replaces the hook
    instead of stacking a second one.
  - Preserve every other key and every other hook event.
  - Copy `settings.json` to `settings.json.bak.<timestamp>` before any edit.
- Write `${CLAUDE_DIR:-$HOME/.claude}/plain-workflow.json` when it is absent.
  - `--reviewer <value>` sets it without a prompt.
  - No flag and a real terminal: prompt with the 4 named engines plus a free-text
    option, and mark which plugins are actually enabled.
  - No terminal, `--dry-run`, or `--check`: never prompt. A non-interactive install
    writes `auto`.
  - An existing config is never overwritten. A malformed one is reported and left
    untouched. Keys a later `config.example.json` adds, such as `jira`, are filled in
    additively without changing values the user already set.
- Flags:
  - `--reviewer <value>` sets the safe-review engine.
  - `--dry-run` prints every action and changes nothing.
  - `--check` exits 0 when the install is current, 1 when it is not.
- Prints a one-line summary at the end.

### uninstall.sh contract

- Removes only the symlinks that point inside this repository.
- Removes the `CLAUDE.md` block and its markers.
- Removes the tagged hook entry, then removes `UserPromptSubmit` and `hooks` if they
  become empty, so an otherwise-untouched `settings.json` returns to its original
  shape.
- Leaves all backups in place.
- Keeps `plain-workflow.json`, so a reinstall does not re-prompt.
- Supports `--dry-run`.

## Out of scope

- No change to the existing `ticket`, `pr-review`, `review-loop`, `caveman`, or
  `simple-english` skills.
- No GitHub remote.
- No team distribution.

## Verification

- `bash -n` passes on both scripts.
- `./install.sh --dry-run` prints the expected actions in a clean state.
- `./install.sh` creates 6 symlinks and writes the `CLAUDE.md` block.
- `./install.sh` a second time reports `ok` 6 times and does not duplicate the block.
- `./install.sh --check` exits 0 after a successful install.
- `./uninstall.sh` removes the 6 symlinks, the block, and the hook entry.
- Each `SKILL.md` has valid frontmatter with `name` and `description`.
- After a backup, `skills/` holds only symlinks. No backup directory remains in it.
- The hook script returns valid JSON when fed a real event payload on stdin.
- `PLAIN_SPEAK_OFF=1` makes the hook produce no output.
- Installing the hook preserves every other key and hook event in `settings.json`.
- A changed repository path replaces the hook entry instead of adding a second one.
- A malformed `settings.json` is reported and left byte-for-byte unchanged.
- Every prompt branch resolves correctly over a real terminal: empty, 1, 2, 3, 4,
  5 plus a typed name, and a pasted name at the first prompt.
- A number outside 1-5 writes no config.
- `--reviewer` and a no-terminal install both skip the prompt.
- An existing config survives a re-run and an uninstall.
- A config written by an older version gains every new key and keeps the values it had.
- A config in the old nested layout migrates to `jira_host` + `jira_keys`, keeps each
  project's strict flag, and is backed up first. A second run is a no-op.
- A partly-filled nested block, such as `jira` with only `host`, keeps that value and
  gains its missing siblings.
- No organisation name, host name, project key, user name, or home path appears in any
  repository file, including the vendored `simple-english`.
- No skill outside this repository is required. The only outside skills named are the
  optional `reviewer` values.
- `/explain-ticket` on a real ticket returns the 5-line shape and stays under 150 words.
