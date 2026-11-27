---
name: write-ticket
description: Draft a Jira or GitHub ticket with an exact scope, an explicit out-of-scope list, testable acceptance criteria, a test plan, and a diagram when a flow or state is involved. Use when the user says "write a ticket", "create an issue", "turn this into a ticket", "draft a Jira", or invokes /write-ticket. Drafts first, asks only for the gaps, and never creates the ticket without approval.
---

# write-ticket

Load `plain-speak` first. Artifacts use full sentences, max 20 words each.

Also load `simple-english`. Jira and GitHub text is technical documentation. The ticket's
project key picks the mode through `jira_keys`. See step 1.

## Workflow

### 1. Detect the tracker

Read `~/.claude/plain-workflow.json` first. Take `jira_host` and `jira_keys`.

`jira_keys` maps a project prefix to its STE mode:

```json
{ "jira_host": "jira.example.com", "jira_keys": { "ENG": "flavored", "REL": "strict" } }
```

| Signal | Tracker |
|---|---|
| The user names a key whose prefix is in `jira_keys` (for example `ENG-42`) | Jira |
| The user names any `KEY-123` and `jira_keys` is empty | Jira, ask for the host once |
| `git remote -v` points at github.com and no Jira key is given | GitHub |
| Neither | Ask once |

The tracker decides the diagram format. Nothing else changes.

`jira_host` empty means Jira is not configured. Do not guess a host. Ask, then offer to
save it:

```
No Jira host configured. Add it to ~/.claude/plain-workflow.json:
  "jira_host": "jira.example.com",
  "jira_keys": { "ENG": "flavored" }
```

### 2. Draft at once

Do not interview first. Write a full draft from whatever the user gave: a sentence, a
conversation, a plan file, a bug report.

Mark every hole as `? NEEDS ANSWER — <what you need>` inside the draft. Do not guess
acceptance criteria. Do not invent scope.

### 3. Ask the gaps, one round

Collect every `? NEEDS ANSWER` into a single `AskUserQuestion` call. Maximum 4
questions. If more than 4 holes exist, the ticket is too vague — say so and ask the
4 that matter most.

Never ask a question the draft already answers.

### 4. Finalise

Fill the answers in. Run the `simple-english` self-lint pass. Show the finished ticket.

### 5. Ask before creating

Show the body. Then ask whether to create it.

- Jira: create through the Atlassian MCP, or
  `gh api -X POST -H "Accept: application/json" https://<jira_host>/rest/api/2/issue`.
  May need a VPN. If the call fails, hand back the body and say the user must paste it.
- GitHub: `gh issue create --title "..." --body-file <file>`.

Never create a ticket without an explicit yes.

## Template

Full template with worked examples: [TEMPLATE.md](TEMPLATE.md)

```
## Problem
1 to 3 sentences. What is wrong or missing, and why it matters now.

## Scope

### In
- testable bullet
- testable bullet

### Not in this ticket
- explicit exclusion
- explicit exclusion

## Acceptance criteria
- [ ] observable outcome, no implementation detail
- [ ] observable outcome, no implementation detail

## Test plan
How a human verifies this by hand, step by step.

## Diagram
(only when a flow, a state change, or a sequence is involved)
```

## Rules

**The out-of-scope list is the point.** It is the one section that stops drift. Never
leave it empty. If nothing is excluded, the ticket is too vague — find the nearby work
a reader would assume is included, and exclude it by name.

**Acceptance criteria are observable.** They describe what a tester sees, not what the
code does.

- Yes: `- [ ] A request with an expired token returns 401.`
- No: `- [ ] Add a token expiry check to the middleware.`

**Size gate.** More than 5 in-scope bullets, or more than 7 acceptance boxes, means the
ticket is too big. Stop. Say `Too big. Split it:` and propose 2 or 3 smaller tickets by
title. Do not draft them unless asked.

**Diagrams.** Add one when the ticket describes a flow, a state machine, or a sequence
between services. Skip it for a single-file change.

| Tracker | Format |
|---|---|
| Jira | ASCII box drawing inside a `{code}` block. Jira does not render Mermaid. |
| GitHub | Mermaid in a ```mermaid fence. GitHub renders it. |

ASCII example:

```
  client ──POST /audit──▶ api ──▶ rate limiter
                          │            │
                          │            └─ over limit ─▶ 429
                          └─ ok ─▶ audit store
```
