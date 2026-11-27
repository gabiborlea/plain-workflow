# plain-workflow

Seven Claude Code skills that keep output short, tickets exact, and pull requests inside
scope.

## Why

Four problems, one cause each:

| Problem | Fix |
|---|---|
| Output too long and too complex | `plain-speak` — a hard voice contract, always on |
| Ticket scope is vague, so the PR drifts | `write-ticket` — an explicit out-of-scope list |
| Tickets are hard to read | `explain-ticket` — a fixed 5-line shape, 120 words |
| Review loops never end | `safe-review` — 3 gates, only merge blockers survive |
| Posting a review means copy and paste | `post-review` — pick what to post, one review |
| Fixes for review comments cause new bugs | `answer-review` — triage, then prove each fix |

## Install

> **Installed plain-workflow before with `install.sh`?** Run `./uninstall.sh` from that
> clone first. See [Coming from install.sh](#coming-from-installsh).

In Claude Code:

```
/plugin marketplace add gabiborlea/plain-workflow
/plugin install plain-workflow@plain-workflow
```

Restart Claude Code afterwards. The plugin brings three things:

1. The skills, from `skills/`.
2. A `SessionStart` hook that adds `CLAUDE-BLOCK.md` to each session.
3. A `UserPromptSubmit` hook that re-adds the short rules on every prompt.

The review engine and the Jira keys live in `~/.claude/plain-workflow.json`. The plugin
does not create it. Copy `config.example.json` there to set them. No file means
`reviewer: auto` and GitHub only. See [Configuration](#configuration).

Remove the plugin with `/plugin uninstall plain-workflow@plain-workflow`.

### Coming from install.sh

Older versions installed with `install.sh`, which is gone. Run `./uninstall.sh` from a
clone before you install the plugin. Otherwise the rules load twice and the hook runs
twice. It removes the skill links, the `CLAUDE.md` block and the hook. It keeps your
`~/.claude/plain-workflow.json`.

The plugin checks for an old setup at each session start. If it finds one, it shows a
warning with the path to `uninstall.sh`, and Claude offers to run it.

```bash
./uninstall.sh --dry-run    # print every action, change nothing
./uninstall.sh
```

### Requirements

| Tool | Needed by |
|---|---|
| `jq` | both hooks (without it they fall back to plain text) |
| `git` | `safe-review`, to find the real fork point |
| `gh`, authenticated | `explain-ticket`, `safe-review`, `post-review`, `answer-review` |
| `python3` | the `simple-english` linter only |

No other skill or plugin is required. `pr-review-toolkit` and `code-review` are engine
choices, and `builtin` needs neither.

## The skills

### plain-speak

No slash command. The other four load it. Holds the voice contract, the scope
contract, and the code-comment rule.

Three layers keep it from fading:

| Layer | When it applies |
|---|---|
| `SessionStart` hook | Adds `CLAUDE-BLOCK.md` once at session start |
| `UserPromptSubmit` hook | Re-injected on **every** prompt, so it never fades in a long session |
| `plain-speak` skill | Loaded on demand for the full rules |

The hook is `hooks/plain-speak-reminder.sh`. It returns the rules as
`additionalContext` with `suppressOutput`, so nothing appears in your transcript.
Silence it for one shell with `PLAIN_SPEAK_OFF=1`, or disable the plugin.

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

**The engine is yours to pick.** Set `reviewer` in `~/.claude/plain-workflow.json`.
No file means `auto`.

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

Output goes to chat. `safe-review` never posts. For a pull request, it hands off to
`post-review`.

### /post-review

Posts a finished `safe-review` as one GitHub review. It asks first, and posts nothing
without an answer.

| Verdict | Questions |
|---|---|
| SAFE TO MERGE | Approve? · Post the optional findings: all, pick which, or none? |
| NOT SAFE | Post the blockers: all, pick which, or none? · The same for the optional findings · Request changes? |

Posted blockers with "Request changes" give `REQUEST_CHANGES`. Approval gives `APPROVE`.
Anything else is a `COMMENT` review. No comment carries a "blocking" or "optional"
label. On your own pull request, GitHub allows comments only.

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

`config.example.json` ships with `jira_keys` empty on purpose. Copied as-is, it must
not turn an example prefix into somebody's real setting.

## Optional companions

None of these are required. The repo works without them.

| Skill | Relationship |
|---|---|
| `pr-review-toolkit` | One `reviewer` option. Not vendored — it rebuilds from `settings.json`. |
| `code-review` | Another `reviewer` option. |
| `pr-review` | Where `scripts/pr-context.sh` came from. It can post a review to GitHub; `post-review` covers that need for `safe-review` output. |
| `caveman` | Not vendored, not loaded. `plain-speak` keeps grammar, which caveman drops. |

## Layout

```
.claude-plugin/     plugin.json, marketplace.json
uninstall.sh        removes an old install.sh setup
config.example.json copy to ~/.claude/plain-workflow.json to set the engine and Jira
CLAUDE-BLOCK.md     added to each session by the SessionStart hook
hooks/
  hooks.json                wires the 2 hooks below
  session-start.sh          SessionStart, adds CLAUDE-BLOCK.md
  plain-speak-reminder.sh   UserPromptSubmit, re-injects the rules each turn
skills/
  plain-speak/SKILL.md
  simple-english/            vendored: SKILL.md, linter.py, lint-hook.sh
  write-ticket/SKILL.md, TEMPLATE.md
  explain-ticket/SKILL.md
  safe-review/SKILL.md, GATES.md
    scripts/pr-context.sh   copied from pr-review, so there is no outside dependency
  post-review/SKILL.md
  answer-review/SKILL.md
```
