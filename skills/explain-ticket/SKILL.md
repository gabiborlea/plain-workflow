---
name: explain-ticket
description: Summarize a Jira or GitHub ticket in about 120 words — what it wants, why, what done looks like, what is not in it, and what is unclear. Use when the user says "explain this ticket", "what does ENG-42 want", "summarize this issue", pastes a ticket body, or invokes /explain-ticket. Does not read code and does not propose an approach.
---

# explain-ticket

Load `plain-speak` first.

One job: make the ticket clear in 10 seconds. Nothing else.

## Input

Read `~/.claude/plain-workflow.json` first for `jira_host`. Then accept any of these:

| Input | Action |
|---|---|
| Jira key (`ENG-42`) | `gh api -H "Accept: application/json" "https://<jira_host>/rest/api/2/issue/<KEY>"` or the Atlassian MCP |
| Jira URL | Take the host and key from the URL |
| GitHub issue or PR URL or number | `gh issue view <n> --json title,body` |
| Pasted text | Use it directly |

`jira_host` empty and no URL given? Ask for the host in one line. Do not guess it.

If the fetch fails (no VPN, no auth), say so in one line and ask the user to paste the
body. Do not guess the content.

## Output — fixed shape, always

```
WHAT        <one sentence>
WHY         <one sentence>
DONE WHEN
  [ ] <acceptance criterion, reworded plain>
  [ ] <acceptance criterion, reworded plain>
NOT IN IT   <out of scope, or "not stated">
UNCLEAR     <open question, or "none">
```

Target 120 words. Hard cap 150.

Reword the acceptance criteria into plain language. Do not copy Jira formatting,
markup, or field noise.

## Hard rules

**Do not read the code.** No `grep`, no `Read`, no file names, no repo exploration.

**Do not propose an approach.** No design, no plan, no "you could do X".

**Do not estimate.** No sizing, no effort.

If you feel the pull to do any of the three, stop. That is drift. The user asked what
the ticket says, not how to build it.

## Missing sections

| Situation | Say this |
|---|---|
| No acceptance criteria | `DONE WHEN — ticket has no acceptance criteria.` Then offer `/write-ticket` to add them. |
| No out-of-scope list | `NOT IN IT — not stated.` Flag it under UNCLEAR as a drift risk. |
| Ticket is one line with no detail | Say `Ticket is too thin to explain.` List the 3 things it must answer. |

## Example

Input: `ENG-42`

```
WHAT        Add a per-API-key rate limit to POST /audit.
WHY         One client sent 40,000 requests on 2026-07-30 and delayed alerts
            by 12 minutes.
DONE WHEN
  [ ] Over 100 requests in 60 seconds from one key returns 429.
  [ ] The 429 carries a Retry-After header.
  [ ] Requests under the limit behave as today.
  [ ] A rejection metric increases.
  [ ] The limit comes from config.
NOT IN IT   Other endpoints. Per-tenant quotas. Audit store changes. Config UI.
UNCLEAR     none
```
