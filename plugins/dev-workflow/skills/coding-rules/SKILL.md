---
name: coding-rules
description: Use when writing, refactoring, or reviewing code - before creating any new function, class, or module.
user-invocable: false
---

# Coding Rules

## Before writing anything

**Search for existing code first.** An existing utility, hook, or pattern that fits the need MUST be reused. Writing a parallel implementation of something that exists is a defect, not a style choice.

## Principles, made concrete

- **SRP** — a unit does one thing. If describing a function honestly requires "and", split it.
- **Open/Closed** — extend via new implementations of existing interfaces, not by adding flags and branches to working code.
- **Liskov** — an implementation that throws "not supported" for part of its interface is the wrong abstraction; narrow the interface instead.
- **Interface segregation** — depend on the few methods you use, not on a god-object.
- **Dependency inversion** — business logic receives its dependencies (injection); it doesn't instantiate clients, DBs, or clocks inline.
- **DRY, rule of three** — extract on the third duplication. Two similar blocks that may diverge are cheaper than a premature abstraction.
- **KISS** — the simplest design that passes the tests wins. No layers "for flexibility".
- **YAGNI** — build only what the current task needs. No speculative parameters, config, or generalization.

## Hygiene

- Small functions, explicit names (`retryDelayMs`, not `d`); the name states intent so the body doesn't need narration.
- Comments only for constraints the code cannot express (invariants, gotchas, "why") — never "what the next line does".
- Handle errors at the boundary where you can act on them; never swallow silently.
- Match the surrounding file's style, naming, and idioms — consistency beats personal preference.

## Red flags — stop and reconsider

- Copy-pasting a block for the third time
- A function name containing "And" / "Or" / "Manager" / "Util"
- Adding a boolean parameter to make old code do a second thing
- Writing a helper before checking whether one exists
