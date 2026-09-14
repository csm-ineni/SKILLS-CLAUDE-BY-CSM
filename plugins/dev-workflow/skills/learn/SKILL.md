---
name: learn
description: Use when the same mistake happens twice, when the user corrects an approach, when the reviewer flags something already seen, or when a guard fires - turns a paid-for mistake into a lesson that cannot be forgotten.
---

# Learn

Research is what we know. Decisions are what we chose. **Lessons are what we got wrong** — and the only memory that defends itself, because a lesson can block the action that repeats it.

## When to write one

Four moments, all of them cheap to recognise:

- The user corrects an approach ("no, not like that").
- The `reviewer` returns *needs work* on something already raised before.
- A test breaks twice for the same underlying reason.
- A guard fires — including an override, which means a lesson was worth stating but stated badly.

A single occurrence is not a lesson. Write the first one in the branch's `## Watch out`; promote it here when it happens again, or immediately if it was expensive.

## Writing one

One lesson per file, `.claude/memory/lessons/<kebab-slug>.md`, frontmatter flat (a single `awk` pass parses every lesson on every tool call):

```markdown
---
rule: Never run prisma migrate without --create-only on the dev database
why: "2026-03-12: lost the local seed, 40 minutes gone"
tools: Bash
pattern: prisma migrate
level: 2
---

Run it with --create-only, read the generated SQL, then apply.
```

- `rule` — imperative, one line, the thing to do or avoid.
- `why` — the incident that paid for it, dated. A rule without a cost is a preference; it will be ignored.
- `tools` — `Bash`, `Edit`, `Write`, comma-separated. For `Bash` the pattern is matched against the command, for `Edit`/`Write` against the file path.
- `pattern` — extended regex (`grep -E`), matched against the Bash command or the edited path. Make it narrow: a pattern that fires on innocent commands trains everyone to ignore lessons.
- `level` — see the ladder below.

Write no counters here. `hits`, `overrides` and `last_hit` used to live in this frontmatter; the guard now keeps them in `.claude/state/lesson-stats.json` (local, gitignored), shaped `{"<slug>": {"hits": N, "overrides": N, "last_hit": "YYYY-MM-DD"}}`. Any such key left in a lesson file is inert — `.claude/memory/` is committed, and counters rewritten on every tool call would keep the tree dirty and turn every branch into a merge conflict.

Omit `tools` or `pattern` and the lesson can only ever be level 1 — the guard skips it, and it is listed by title at session start.

Then run `plugins/dev-workflow/scripts/memory-index.sh` to refresh the index. Never edit `INDEX.md` by hand.

## The ladder

| Level | Effect | When |
|---|---|---|
| 1 | Title listed at session start | First write-up, or no reliable pattern |
| 2 | Full lesson surfaced when the pattern matches | Second occurrence |
| 3 | Action **blocked**, escape hatch printed | Third occurrence, or an expensive mistake from the start |

A rule that has to be repeated is a rule that failed. Promoting to level 3 is admitting prose is no longer enough — the same admission `guard-commit.sh` already embodies for Claude attribution.

## Escape hatch and demotion

Level 3 has two escape hatches, both naming the slug explicitly:

| Tool | How |
|---|---|
| `Bash` | Prefix the command: `DW_OVERRIDE=<slug> <your command>`. The prefix must open the command — a `DW_OVERRIDE=` sitting in a trailing comment bypasses nothing. |
| `Bash`, `Edit`, `Write` | Set `DW_OVERRIDE=<slug>` in the session environment. This is the only channel for `Edit`/`Write`: there is no command to prefix. |

Counters (levels 2 and 3 only; level 1 is never matched) live in `.claude/state/lesson-stats.json`: `hits` counts every surfacing and every block, `overrides` every bypass. Read them there — `cat .claude/state/lesson-stats.json` — never from a lesson file.

**A lesson that is often overridden is a bad lesson.** At `overrides >= 3` in that file, do not tighten it — fix it: narrow the `pattern`, split it into two lessons, or demote it to level 2. That counter is the feedback loop that keeps this memory honest.

## Deduplicating and retiring

Before writing, read the existing lessons: a near-duplicate must be *edited*, never added alongside — two lessons saying almost the same thing halve the credibility of both. A lesson untriggered for six months (`last_hit` in `.claude/state/lesson-stats.json`) moves to `.claude/memory/lessons/archive/`, keeping the active set small enough to be read; archived lessons are no longer matched or listed. Nothing prunes `.claude/state/lesson-stats.json`, so when archiving or deleting a lesson, drop its slug from that file too — otherwise its counters outlive it and mislead the next reader.
