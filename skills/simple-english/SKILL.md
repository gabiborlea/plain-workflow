---
name: simple-english
description: MANDATORY for all technical documentation and all ticket content. Full ASD-STE100 Simplified Technical English reference — substitution tables, approved verb forms, noun-cluster repair, procedure and safety-text patterns, and a linter. Load before you write or rewrite any README, design doc, runbook, procedure, safety text, error-message catalog, API doc, architecture note, PR description, or Jira or GitHub ticket summary, description, or comment. Also load when asked to audit prose for STE compliance. The condensed core rules live in the global CLAUDE.md and cover short routine text.
---

# ASD-STE100 — working reference

ASD-STE100 is the Simplified Technical English specification, written in 1986 for aircraft
maintenance manuals and maintained by the AeroSpace and Defence Industries Association of
Europe. It exists so that a reader with weak English can not misread a procedure. It
constrains vocabulary to roughly 900 approved words plus unlimited domain-specific
technical names, and it constrains grammar to a small set of forms.

This file is an abridgment of Part 1 (Writing Rules). It is not the standard and not a
certification. Get the free official PDF at https://asd-ste100.org. Do not paste the
standard into a repository. It is copyrighted.

## Modes

Pick a mode before you write. State it if it is not obvious.

**strict** — procedures, runbooks, safety text, error messages, checklists, anything a
tired person reads at 3 a.m. Apply every rule. Enforce both word caps. Stay inside the
approved-word spirit: if a plain word exists, use it.

**STE-flavored** — READMEs, design docs, PR descriptions, code comments, chat replies.
Apply sentence length, paragraph length, active voice, approved verb forms, noun-cluster
limits, and the banned-word lists. Relax the ~900-word dictionary lockdown so the text
keeps enough range to read naturally.

**off** — marketing copy, essays, fiction, anything where voice is the product. Say that
you are dropping STE. Keep sentence length and active voice anyway. They cost nothing.

### Mode selection (not optional)

STE is mandatory for technical documentation and ticket content. Use this table.

| Text | Mode |
|---|---|
| Runbook, procedure, checklist, safety text, error message | strict |
| Release or deployment ticket | strict |
| README, design doc, architecture note, API doc, PR description | STE-flavored |
| Any other ticket, issue, or comment | STE-flavored |

Which project counts as release or deployment is configuration, not a rule. Read
`jira_keys` from `~/.claude/plain-workflow.json`. It maps a project prefix to that
project's mode.

```json
{ "jira_keys": { "ENG": "flavored", "REL": "strict" } }
```

A ticket in `REL` gets **strict**. A prefix that is absent, or a value that is not
`strict`, gets **STE-flavored**. No config file means only the document type decides.

Chat replies to the user stay outside this rule. Write them plainly.

Run the self-lint pass below on every draft before you return it or send it to the
tracker. Do not report the pass. Just fix.

## Rule 1 — Words

### One thing, one name
Choose a name for each item and never vary it. Synonym variation is a readability bug, not
style. `the worker` stays `the worker`. It does not become `the process`, `the job`, or
`the runner` three paragraphs later.

### One word, one meaning
Each word carries a single approved sense.

| Word | Approved sense | Not this sense |
|---|---|---|
| fall | move down | decrease |
| follow | come after | obey |
| close | shut | near |
| clear | remove obstruction | obvious |
| free | not attached | no cost |
| like | similar to | enjoy |
| since | (avoid) | because / from a time |
| while | (avoid) | although / during |
| as | (avoid) | because / at the same time |

Replace `since`, `while`, and `as` with `because`, `although`, or `during`. Each one is
ambiguous.

### Substitutions

| Do not write | Write |
|---|---|
| utilize, leverage | use |
| initiate, commence, begin | start |
| terminate, cease | stop, end |
| facilitate, enable (of a person) | help |
| ensure, guarantee | make sure |
| prior to, in advance of | before |
| subsequent to, following | after |
| in the event that, in case of | if |
| in order to | to |
| due to the fact that, owing to | because |
| regarding, concerning, with respect to | about |
| obtain, acquire, procure | get |
| demonstrate, illustrate | show |
| additionally, furthermore, moreover | also |
| therefore, thus, hence, consequently | so |
| however, nevertheless, nonetheless | but |
| approximately | about |
| sufficient | enough |
| numerous, a multitude of | many |
| the majority of | most |
| at this point in time | now |
| in the vicinity of | near |
| is capable of | can |
| has the ability to | can |
| it is necessary that | must |
| attempt | try |
| assist | help |
| require | need |
| modify | change |
| indicate | show |
| permit | let |
| retain | keep |
| transmit | send |
| verify | check |
| identify | find |

### Banned: marketing adjectives and adverbs
seamless, robust, powerful, cutting-edge, state-of-the-art, world-class, next-generation,
revolutionary, game-changing, effortless, blazing-fast, lightning-fast, delightful,
elegant, beautiful, incredible, amazing, simply, easily, just, merely, actually, basically,
essentially, arguably, quite, very, extremely, incredibly.

Delete them. If the claim matters, prove it with a number.

### Banned: filler openers and closers
"It is important to note that", "It is worth mentioning that", "It should be noted that",
"In today's fast-paced world", "At the end of the day", "Let's dive in", "In conclusion",
"I hope this helps", "Feel free to".

Delete the opener and start at the content. Delete the closer and stop.

### Banned: phrasal verbs
| Do not write | Write |
|---|---|
| spin up, stand up | start, create |
| tear down, blow away | delete, remove |
| track down | find |
| carry out, perform | do |
| set up | install, configure |
| turn on / off | enable / disable |
| come up with | design, choose |
| figure out | solve, determine |
| go through | read, check |
| take care of | handle, do |
| put in place | install, add |

### Keep the small words
STE requires articles and relative pronouns. Do not delete them for brevity.

- Write `the file that you edited`, not `the file you edited`.
- Write `make sure that the service runs`, not `make sure the service runs`.
- Write `remove the cover and the gasket`, not `remove the cover, gasket`.

### Other word rules
- American spelling: color, behavior, analyze, license (verb and noun).
- No contractions: `do not`, `cannot`, `it is`.
- No Latin abbreviations: use `for example` (not e.g.), `that is` (not i.e.), `and so on`
  (not etc.).
- Spell out an abbreviation on first use. After that, use it consistently.
- Do not invent verbs from nouns: `log the error`, not `error out`. `send a request`, not
  `request out`.

## Rule 2 — Noun clusters: three words maximum

A cluster of four or more nouns forces the reader to guess which noun modifies which.
Break it with prepositions.

| Do not write | Write |
|---|---|
| runway light approach system | approach system for the runway lights |
| database connection pool timeout value | timeout value for the database connection pool |
| user account password reset request | request to reset the password of a user account |
| build pipeline artifact retention policy | retention policy for artifacts from the build pipeline |

Hyphenate a compound modifier so its scope is unambiguous: `high-frequency filter`,
`read-only mount`, `two-stage build`.

## Rule 3 — Verbs

### Approved forms only
1. Infinitive — `to start the service`
2. Imperative — `Start the service.`
3. Simple present — `The service starts.`
4. Simple past — `The service started.`
5. Past participle as an adjective — `the configured service`
6. Future with `will` — `The service will start.`
7. Modals `can` and `must`

Everything else is out.

| Do not write | Write |
|---|---|
| has been configured | is configured |
| had been running | ran |
| will have completed | completes |
| is starting | starts |
| the process is running | the process runs |
| having read the file | after you read the file |
| the file being read | the file that the parser reads |
| should be able to | can |
| might potentially | can |
| may be required to | must |

### Active voice
Name the actor. `The parser reads the file.` Not `The file is read by the parser.` Not
`The file is read.`

Passive is allowed in one place: a warning where the actor is unknown, irrelevant, or the
reader. `The disk can be damaged.`

### Verbs, not nominalizations
| Do not write | Write |
|---|---|
| perform an analysis of | analyze |
| make a decision about | decide |
| provide a description of | describe |
| give consideration to | consider |
| do an installation of | install |
| effect a change to | change |
| is a requirement for | needs |

### No stacked auxiliaries
`It is important to note that this may help to improve performance` becomes
`This improves performance.` If it does not improve performance, say what it does.

## Rule 4 — Sentences

- Instruction: 20 words maximum.
- Descriptive: 25 words maximum.
- One instruction per sentence. Two actions means two sentences or a list.
- Start an instruction with its command verb: `Open the valve.` not `The valve must now be
  opened by the technician.`
- Put the condition first: `If the pressure is low, close the valve.` The reader must know
  whether the instruction applies before they read the action.
- Use a pronoun only when its noun is unmistakable. Repeat the noun otherwise. Two nouns in
  a sentence means no `it`.
- Do not start a sentence with a conjunction in strict mode.

## Rule 5 — Paragraphs

- One topic per paragraph. Six sentences maximum.
- Put the topic in the first sentence.
- Keep related information together. Do not split one procedure across two paragraphs.
- Use a vertical list when text holds more than three linked items or conditions.

## Rule 6 — Procedures

Write each step as a command.

```
1. Set the switch to OFF.
2. Disconnect the power cable.
3. If the indicator stays on, wait 30 seconds.
4. Remove the cover.
```

Rules:
- One action per numbered item. Two actions means two items.
- Imperative form, command verb first.
- Do not number descriptive text. Numbers mean "do this in this order".
- Give the result if the reader must confirm it: `The indicator goes off.`
- Do not write `simply`, `just`, or `merely`. If the step is easy, the reader finds out.

## Rule 7 — Safety text

Put the warning before the step. A warning after the step is useless.

```
WARNING: The capacitor holds a charge for 10 minutes. You can get an
electric shock.

1. Wait 10 minutes after you remove power.
2. Discharge the capacitor.
```

- **WARNING** — a person can be injured or killed.
- **CAUTION** — equipment or data can be damaged.
- **NOTE** — useful information. Not a hazard.

Structure: state the hazard, then the consequence, then the action to avoid it. Use the
imperative. Keep it under 20 words per sentence.

## Rule 8 — Descriptive writing

Descriptive text answers what, where, when, who, and why. It does not command.

- Keep the same rules on words, verbs, and clusters.
- 25 words per sentence.
- Do not mix description into a numbered procedure. Put it before or after the list.
- Use the present tense for how a thing works. `The valve opens at 30 psi.`

## Rule 9 — Error and log messages

- State what failed, then why, then what the reader must do.
- Name the actor and the object. `The parser cannot read config.yaml. The file does not
  exist. Create the file or set --config.`
- No apology, no exclamation marks, no humor.
- One sentence per idea. No semicolons.
- Keep the message under 25 words when you can.

## Self-lint

Run this pass on every draft before you return it. Do not report the pass. Just fix.

1. Sentence over 20 words (instruction) or 25 (descriptive) → split it.
2. Semicolon → period. Slash meaning "and/or" → the words. Latin abbreviation → English.
3. Contraction → expand.
4. Passive voice with a knowable actor → active.
5. Perfect tense, progressive tense, or `-ing` main verb → simple tense.
6. Nominalization or phrasal verb → plain verb.
7. Marketing adjective, intensifier, or filler opener → delete.
8. Noun cluster over three words → break with a preposition.
9. Same thing under two names → one name.
10. Dropped article or relative pronoun → put it back.
11. Condition after its command → move the condition first.
12. Warning after its step → move the warning first.

## Linter

`linter.py` in this skill directory checks the mechanical subset. It scores violations per
100 words. Lower is cleaner.

```bash
python3 ~/.claude/skills/simple-english/linter.py draft.md
python3 ~/.claude/skills/simple-english/linter.py draft.md --strict
```

No dependencies beyond Python 3. It skips code fences, inline code, URLs, headings, and
tables.

It is a heuristic aid, not a certified STE checker. It grades prose. It over-fires on rule
catalogs, glossaries, and any text that quotes the banned words to define them, because it
cannot tell use from mention. Read the findings. Do not chase the score to zero.

## What this cannot do

STE fixes the form of bad writing. It cannot make a hollow paragraph true, and it cannot
choose the right technical noun for you. A document that passes every rule above can still
say nothing. Check that each paragraph carries a fact the reader did not have.
