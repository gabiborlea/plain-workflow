# plain-workflow

Six Claude Code skills that keep output short, tickets exact, and pull requests inside
scope.

## Why

Four problems, one cause each:

| Problem | Fix |
|---|---|
| Output too long and too complex | `plain-speak` — a hard voice contract, always on |
| Ticket scope is vague, so the PR drifts | `write-ticket` — an explicit out-of-scope list |
| Tickets are hard to read | `explain-ticket` — a fixed 5-line shape, 120 words |
| Review loops never end | `safe-review` — 3 gates, only merge blockers survive |
| Fixes for review comments cause new bugs | `answer-review` — triage, then prove each fix |

## Install

```bash
git clone <this repo> plain-workflow
cd plain-workflow
./install.sh
```

Clone it anywhere. `install.sh` resolves its own path, and the symlinks point back to
wherever you put it.

Four things happen:

1. Each skill is symlinked into `~/.claude/skills/`.
2. A condensed rule block is written into `~/.claude/CLAUDE.md` between markers.
3. A `UserPromptSubmit` hook is added to `~/.claude/settings.json`.
4. It asks which review engine `safe-review` should use, and saves the answer to
   `~/.claude/plain-workflow.json`.

An existing config is never overwritten. Keys added by a later version, such as
`jira`, are filled in without touching values you already set.

Restart Claude Code afterwards, or open `/hooks` once to reload the config.

### Requirements

`install.sh` runs a preflight and reports each one. A missing tool is a warning, never
a hard stop.

| Tool | Needed by |
|---|---|
| `jq` | `install.sh` (hook and config), the reminder hook |
| `git` | `safe-review`, to find the real fork point |
| `gh`, authenticated | `explain-ticket`, `safe-review`, `answer-review` |
| `python3` | the `simple-english` linter only |

No other skill or plugin is required. `pr-review-toolkit` and `code-review` are engine
choices, and `builtin` needs neither.

```bash
./install.sh --reviewer builtin   # set the engine, skip the prompt
./install.sh --dry-run            # print every action, change nothing
./install.sh --check              # exit 0 if current, 1 if not
./uninstall.sh                    # remove links, block, and hook
```

The prompt is skipped when `--reviewer` is given, when the config already exists, or
when there is no terminal. A non-interactive install defaults to `auto`, so CI and
piped installs never hang.

`install.sh` is safe to re-run. A real directory in the way is moved to
`~/.claude/.plain-workflow-backups/<name>.<timestamp>`, never deleted. Backups must
stay outside `skills/`, because Claude Code scans every directory in there and would
register a backup as a second, duplicate skill.

`CLAUDE.md` and `settings.json` are each copied to `<name>.bak.<timestamp>` before any
edit. A malformed `settings.json` is reported and left untouched.

Set `CLAUDE_DIR` to target a different config directory.

## The skills

### plain-speak

No slash command. The other four load it. Holds the voice contract, the scope
contract, and the code-comment rule.

Three layers keep it from fading:

| Layer | When it applies |
|---|---|
| `CLAUDE.md` block | Loaded once at session start |
| `UserPromptSubmit` hook | Re-injected on **every** prompt, so it never fades in a long session |
| `plain-speak` skill | Loaded on demand for the full rules |

The hook is `hooks/plain-speak-reminder.sh`. It returns the rules as
`additionalContext` with `suppressOutput`, so nothing appears in your transcript.
Silence it for one shell with `PLAIN_SPEAK_OFF=1`, or run `./uninstall.sh` to remove
it.

**Voice:** STE grammar, caveman brevity. Chat replies allow fragments and cap at 150
words. Jira and GitHub text uses full sentences, max 20 words each.

**Scope contract:** the ticket or PR scope is a contract. No "while I was in there"
changes.

**Comments:** only the non-obvious *why*.

### /write-ticket

Drafts a ticket, marks holes `? NEEDS ANSWER`, asks them in one round, then finalises.
Never creates the ticket without a yes.

Your tracker lives in `~/.claude/plain-workflow.json`, not in the skill:

```json
{
  "jira_host": "jira.example.com",
  "jira_keys": { "ENG": "flavored", "REL": "strict" }
}
```

An empty `jira_host` means GitHub only. `write-ticket` and `explain-ticket` both read
it, and neither guesses a host.

### simple-english

Vendored, not written here. It is the full ASD-STE100 reference plus a linter.
`plain-speak` and `write-ticket` both depend on it, so it lives in this repo to stay
tracked and portable instead of existing on one machine only.

Which projects get **strict** mode is configuration, not a rule. It comes from the same
`jira_keys` map. See [strict and flavored](#strict-and-flavored) below.

With no config, only the document type decides: runbooks, procedures, checklists, and
safety text are strict, everything else is STE-flavored.

`caveman` is deliberately **not** here. Nothing in plain-workflow loads it. Its rules
contradict STE — it drops articles and uses fragments, STE requires neither. The
brevity discipline was rewritten into `plain-speak`; the grammar was left behind.

Sections: Problem, Scope (in and **not in this ticket**), Acceptance criteria as
checkboxes, Test plan, Diagram.

Diagrams: ASCII for Jira, Mermaid for GitHub. Jira does not render Mermaid.

Size gate: more than 5 in-scope bullets or 7 acceptance boxes means split it.

### /explain-ticket

```
WHAT        one sentence
WHY         one sentence
DONE WHEN   acceptance criteria as checkboxes, reworded plain
NOT IN IT   out of scope, or "not stated"
UNCLEAR     open questions, or "none"
```

Does not read code. Does not propose an approach. Does not estimate.

### /safe-review

Answers one question: is this safe for main?

**The engine is yours to pick.** `install.sh` asks once and writes the answer to
`~/.claude/plain-workflow.json`. Edit that file any time.

| `reviewer` | What runs |
|---|---|
| `auto` | First present of: `pr-review-toolkit:review-pr`, `code-review`, `builtin` |
| `pr-review-toolkit:review-pr` | Full multi-agent sweep |
| `code-review` | One lighter pass |
| `builtin` | `safe-review`'s own narrow pass. No plugin needed. |
| any other name | Treated as a skill, agent, or slash command and invoked |

A configured engine that is missing gets one warning line, then falls back to
`builtin`. `safe-review` never stops over it.

Whatever the engine, every finding then passes three gates:

1. **Introduced** by this diff, measured from the real fork point.
2. **Blocking** — breaks an acceptance criterion, or is unsafe for main (security,
   leaked secret, data loss, crash, silent error swallow, broken existing behaviour).
3. **Verified** — a `file:line` plus input → wrong result.

Fail any gate and the finding drops to a list of at most 5 optional notes. The engine
is swappable. The filter is not.

Output goes to chat. Use the existing `pr-review` skill to post on GitHub.

### /answer-review

Triages every review comment as REAL, FALSE POSITIVE, or OUT OF SCOPE, each with
`file:line` evidence. Unsure means REAL. FALSE POSITIVE needs the quoted line that
disproves the claim.

You approve which REAL items to fix. Each fix then needs three proofs:

- **Attacker re-read** — what else this could break, and why it does not.
- **Test output** — real and pasted. No "should pass".
- **AC recheck** — the acceptance criteria still hold after all fixes.

OUT OF SCOPE items get a short PR reply and a follow-up ticket draft.

## Configuration

Everything org-specific lives in `~/.claude/plain-workflow.json`, outside the repo, so
`git pull` never conflicts with it.

Shipped defaults, all empty, so a fresh clone assumes nothing about your organisation:

```json
{
  "reviewer": "auto",
  "jira_host": "",
  "jira_keys": {}
}
```

A filled-in example:

```json
{
  "reviewer": "pr-review-toolkit:review-pr",
  "jira_host": "jira.example.com",
  "jira_keys": {
    "ENG": "flavored",
    "SUP": "flavored",
    "REL": "strict"
  }
}
```

| Key | Effect |
|---|---|
| `reviewer` | Which engine `safe-review` runs. See above. |
| `jira_host` | Your Jira host. Empty means GitHub only. |
| `jira_keys` | Project prefix to STE mode. Presence marks the prefix as a Jira ticket; the value is `strict` or `flavored`. |

### strict and flavored

The two writing modes from `simple-english`. They control how hard STE is applied to a
ticket's text.

| Mode | What it enforces | Use it for |
|---|---|---|
| `strict` | Every rule. Both word caps. Stays inside the ~900-word approved dictionary. | Release and deployment tickets, runbooks, procedures, safety text, error messages. Anything a tired person reads at 3 a.m. |
| `flavored` | Sentence length, active voice, approved verb forms, noun-cluster limit, banned-word lists. Drops the ~900-word dictionary, so the text keeps normal range. | Ordinary feature and bug tickets, design notes, PR descriptions. |

`flavored` is also the fallback. A prefix with a missing or unrecognised value gets it.

Listing a project as `flavored` therefore changes nothing by itself. The **key** still
matters: presence in `jira_keys` is how `write-ticket` knows `ENG-42` is a Jira ticket
and not a GitHub issue. Only `strict` changes behaviour.

One map, not two lists. A project appears once and carries its own mode.

`config.example.json` ships with `jira_keys` empty on purpose. It seeds a fresh
config, so any example prefix in it would become somebody's real setting.

`install.sh` adds keys a newer version introduces, migrates an older layout, and never
changes a value you set.

## Optional companions

None of these are required. The repo works without them.

| Skill | Relationship |
|---|---|
| `pr-review-toolkit` | One `reviewer` option. Not vendored — it rebuilds from `settings.json`. |
| `code-review` | Another `reviewer` option. |
| `pr-review` | Where `scripts/pr-context.sh` came from. It can post a review to GitHub; `safe-review` never does. |
| `caveman` | Not vendored, not loaded. `plain-speak` keeps grammar, which caveman drops. |

## Layout

```
install.sh          idempotent, --dry-run, --check, --reviewer
uninstall.sh
config.example.json copied to ~/.claude/plain-workflow.json on first install
CLAUDE-BLOCK.md     injected into ~/.claude/CLAUDE.md between markers
hooks/
  plain-speak-reminder.sh   UserPromptSubmit, re-injects the rules each turn
docs/specs/         design
skills/
  plain-speak/SKILL.md
  simple-english/            vendored: SKILL.md, linter.py, lint-hook.sh
  write-ticket/SKILL.md, TEMPLATE.md
  explain-ticket/SKILL.md
  safe-review/SKILL.md, GATES.md
    scripts/pr-context.sh   copied from pr-review, so there is no outside dependency
  answer-review/SKILL.md
```
