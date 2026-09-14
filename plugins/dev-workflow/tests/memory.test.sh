#!/usr/bin/env bash
# Tests for memory-index.sh: deterministic, atomic index regeneration.
set -u

SCRIPTS="$(cd "$(dirname "$0")/../scripts" && pwd)"
. "$(dirname "$0")/lib.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

bash -n "$SCRIPTS/memory-index.sh" || fail=1

M="$WORK/proj/.claude/memory"
mkdir -p "$M/research" "$M/lessons"

cat > "$M/research/prisma-migrate.md" <<'EOF'
---
topic: Prisma migrate on a shadow database
answer: Use --create-only then review the SQL before applying.
date: 2026-08-01
---
Body ignored by the index.
EOF

cat > "$M/lessons/no-blind-migrate.md" <<'EOF'
---
rule: Never run prisma migrate without --create-only on the dev database
why: "2026-03-12: lost the local seed, 40 minutes gone"
tools: Bash
pattern: prisma migrate
level: 2
hits: 3
overrides: 0
last_hit: 2026-09-02
---
Run it with --create-only, read the SQL, then apply.
EOF

# A legacy entry with no frontmatter must still be indexed.
cat > "$M/research/legacy-note.md" <<'EOF'
# Vitest globals

Set `globals: true` in vitest.config.ts to avoid importing describe/it.
EOF

run() { CLAUDE_PROJECT_DIR="$WORK/proj" bash "$SCRIPTS/memory-index.sh"; }

run
idx="$M/INDEX.md"
check_contains index-research  "prisma-migrate.md" "$(cat "$idx")"
check_contains index-answer    "--create-only"     "$(cat "$idx")"
check_contains index-lesson    "no-blind-migrate"  "$(cat "$idx")"
check_contains index-legacy    "Vitest globals"    "$(cat "$idx")"
check_contains index-has-date  "2026-08-01"        "$(cat "$idx")"

# Hit counts come from .claude/state/lesson-stats.json, never from the frozen
# `hits:` key still sitting in a lesson's frontmatter.
check_contains index-hits-zero-without-stats "[L2, 0 hit(s)]" "$(cat "$idx")"
check_lacks    index-hits-ignores-frontmatter "3 hit(s)"      "$(cat "$idx")"

mkdir -p "$WORK/proj/.claude/state"
cat > "$WORK/proj/.claude/state/lesson-stats.json" <<'EOF'
{
  "no-blind-migrate": {"hits": 7, "overrides": 2, "last_hit": "2026-09-10"},
  "some-other-lesson": {"hits": 41, "overrides": 0, "last_hit": "2026-09-11"}
}
EOF
run
check_contains index-hits-from-stats "[L2, 7 hit(s)]" "$(cat "$idx")"

# Deterministic: regenerating twice yields byte-identical output.
cp "$idx" "$WORK/first.md"
run
check index-deterministic "" "$(diff "$WORK/first.md" "$idx")"

# Atomic: no temp file left behind.
check index-no-temp "0" "$(find "$M" -name '.dw.*' | wc -l | tr -d ' ')"

# Archived lessons are excluded.
mkdir -p "$M/lessons/archive"
cat > "$M/lessons/archive/old.md" <<'EOF'
---
rule: An archived rule nobody needs
level: 1
---
EOF
run
check_lacks index-skips-archive "An archived rule" "$(cat "$idx")"

# Empty memory is a valid state, not an error.
mkdir -p "$WORK/empty/.claude/memory"
CLAUDE_PROJECT_DIR="$WORK/empty" bash "$SCRIPTS/memory-index.sh" >/dev/null 2>&1
check index-empty-exit-zero 0 "$?"

# --- a hand-written index is backed up, loudly, before being replaced ---
H="$WORK/hand/.claude/memory"
mkdir -p "$H/research"
printf '# My notes\nHANDWRITTEN-MARKER\n' > "$H/INDEX.md"
err=$(CLAUDE_PROJECT_DIR="$WORK/hand" bash "$SCRIPTS/memory-index.sh" 2>&1 >/dev/null)
check_contains index-backup-content "HANDWRITTEN-MARKER" "$(cat "$H/INDEX.md.bak" 2>/dev/null)"
check_lacks index-backup-replaced "HANDWRITTEN-MARKER" "$(cat "$H/INDEX.md")"
check_contains index-backup-announced "INDEX.md.bak" "$err"

# A generated index is overwritten silently: there is nothing to lose.
rm -f "$H/INDEX.md.bak"
err=$(CLAUDE_PROJECT_DIR="$WORK/hand" bash "$SCRIPTS/memory-index.sh" 2>&1 >/dev/null)
[ -e "$H/INDEX.md.bak" ] && { echo "FAIL index-no-backup-when-generated"; fail=1; } || echo "PASS index-no-backup-when-generated"
check index-no-backup-silent "" "$err"

report memory
