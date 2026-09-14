#!/usr/bin/env bash
# Tests for lesson-guard.sh: level 2 warns, level 3 blocks, override passes.
set -u

SCRIPTS="$(cd "$(dirname "$0")/../scripts" && pwd)"
. "$(dirname "$0")/lib.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

bash -n "$SCRIPTS/lesson-guard.sh" || fail=1

L="$WORK/proj/.claude/memory/lessons"
mkdir -p "$L"

cat > "$L/no-blind-migrate.md" <<'EOF'
---
rule: Never run prisma migrate without --create-only on the dev database
why: "2026-03-12: lost the local seed"
tools: Bash
pattern: prisma migrate
level: 2
hits: 0
overrides: 0
last_hit: 2026-01-01
---
Run it with --create-only, read the SQL, then apply.
EOF

cat > "$L/never-force-push.md" <<'EOF'
---
rule: Never force-push a shared branch
why: "2026-05-02: wiped a colleague's commits"
tools: Bash
pattern: push .*--force
level: 3
hits: 0
overrides: 0
last_hit: 2026-01-01
---
Use --force-with-lease, after checking nobody else pushed.
EOF

cat > "$L/env-files-are-secret.md" <<'EOF'
---
rule: Never write secrets into a tracked .env file
why: "2026-06-01: pushed a live key"
tools: Edit, Write
pattern: \.env($|\.)
level: 3
hits: 0
overrides: 0
last_hit: 2026-01-01
---
Put it in .env.local, which is gitignored.
EOF

guard() { # <json> -> exit code
  printf '%s' "$1" | CLAUDE_PROJECT_DIR="$WORK/proj" bash "$SCRIPTS/lesson-guard.sh" >/dev/null 2>&1
  echo $?
}
guard_err() { # <json> -> stderr
  printf '%s' "$1" | CLAUDE_PROJECT_DIR="$WORK/proj" bash "$SCRIPTS/lesson-guard.sh" 2>&1 >/dev/null
}

bash_json() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
edit_json() { printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1"; }

# --- no match: silent, allowed ---
check no-match-allows 0 "$(guard "$(bash_json 'ls -la')")"
check no-match-silent "" "$(guard_err "$(bash_json 'ls -la')")"

# --- level 2: allowed, but the lesson is surfaced ---
check level2-allows 0 "$(guard "$(bash_json 'npx prisma migrate dev')")"
check_contains level2-surfaces "create-only" "$(printf '%s' "$(bash_json 'npx prisma migrate dev')" | CLAUDE_PROJECT_DIR="$WORK/proj" bash "$SCRIPTS/lesson-guard.sh" 2>&1)"

# --- level 3: blocked ---
check level3-blocks 2 "$(guard "$(bash_json 'git push --force origin main')")"
check_contains level3-explains "force-with-lease" "$(guard_err "$(bash_json 'git push --force origin main')")"
check_contains level3-offers-escape "DW_OVERRIDE=never-force-push" "$(guard_err "$(bash_json 'git push --force origin main')")"

# --- the escape hatch lets it through and is counted ---
check override-allows 0 "$(guard "$(bash_json 'DW_OVERRIDE=never-force-push git push --force origin main')")"
check_contains override-counted "overrides: 1" "$(cat "$L/never-force-push.md")"

# an override naming a DIFFERENT lesson must not unlock this one
check override-wrong-slug 2 "$(guard "$(bash_json 'DW_OVERRIDE=no-blind-migrate git push --force origin main')")"

# --- Edit/Write match on the file path ---
check edit-blocked 2 "$(guard "$(edit_json '/proj/api/.env')")"
check edit-allowed 0 "$(guard "$(edit_json '/proj/api/config.ts')")"
# a lesson scoped to Edit/Write must not fire on Bash
check tools-scoped 0 "$(guard "$(bash_json 'cat .env')")"

# --- counters ---
hits_before=$(grep '^hits:' "$L/no-blind-migrate.md" | sed 's/hits: //')
guard "$(bash_json 'npx prisma migrate dev')" >/dev/null
hits_after=$(grep '^hits:' "$L/no-blind-migrate.md" | sed 's/hits: //')
[ "$hits_after" -gt "$hits_before" ] && echo "PASS hits-incremented" || { echo "FAIL hits-incremented"; fail=1; }
check_contains last-hit-dated "$(date -u +%Y-%m-%d)" "$(cat "$L/no-blind-migrate.md")"

# --- a malformed lesson must never block work ---
printf 'this is not a lesson at all\n' > "$L/broken.md"
check malformed-allows 0 "$(guard "$(bash_json 'ls')")"

# --- an invalid regex must never block work ---
cat > "$L/bad-regex.md" <<'EOF'
---
rule: Broken pattern
tools: Bash
pattern: "[unclosed"
level: 3
hits: 0
overrides: 0
---
EOF
check bad-regex-allows 0 "$(guard "$(bash_json 'ls')")"
rm -f "$L/bad-regex.md" "$L/broken.md"

# --- no lessons directory at all ---
mkdir -p "$WORK/bare"
printf '%s' "$(bash_json 'git push --force')" | CLAUDE_PROJECT_DIR="$WORK/bare" bash "$SCRIPTS/lesson-guard.sh" >/dev/null 2>&1
check no-lessons-dir 0 "$?"

report lessons
