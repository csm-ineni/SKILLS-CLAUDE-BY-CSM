# dev-workflow — sessions parallèles et apprentissage continu : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Donner au plugin dev-workflow un état de travail scopé par branche, un registre des sessions vivantes, et une troisième mémoire — les leçons — qui empêche mécaniquement la répétition des mêmes erreurs.

**Architecture:** Une bibliothèque shell commune (`lib/state.sh`) porte le calcul du slug de branche, la résolution des chemins et l'écriture atomique ; les hooks existants sont remaniés pour s'en servir, et trois hooks nouveaux s'ajoutent (`SessionEnd`, un garde-fou de leçons sur `PreToolUse`, un générateur d'index mémoire). Tout est du bash POSIX-compatible testé par des tests à entrées en or, sans dépendance nouvelle.

**Tech Stack:** bash, git, `jq`/`python3` (déjà requis par `guard-commit.sh`), hooks Claude Code, skills markdown.

**Spec:** `docs/superpowers/specs/2026-09-14-dev-workflow-multi-sessions-learning-design.md`

## Global Constraints

- **Cible :** Claude Code CLI 2.1.268. Plugin `plugins/dev-workflow`, version portée à `0.4.0`.
- **Un hook cassé ne doit jamais empêcher de travailler.** Tout script sort en `0` en cas d'anomalie (répertoire absent, JSON malformé, hors dépôt git, leçon invalide). Les seules sorties non nulles délibérées : `exit 2` de `guard-commit.sh` et `exit 2` d'une leçon de niveau 3 qui matche ; `exit 1` uniquement pour signaler l'absence de parseur JSON.
- **Parsing JSON :** `jq`, sinon `python3`, sinon `python`, sinon avertissement sur stderr + `exit 1`. Idiome existant de `scripts/guard-commit.sh:9-37` — le réutiliser, ne pas en inventer un autre.
- **Aucune écriture dans l'arbre de travail** hors `.claude/state/` et `.claude/memory/`. Les timbres de throttle restent dans `${XDG_CACHE_HOME:-$HOME/.cache}/claude-dev-workflow`.
- **Écritures atomiques :** fichier temporaire dans le répertoire cible puis `mv -f`. Jamais de `>` direct sur un fichier d'état partagé.
- **Portabilité macOS + Linux :** pas de `date -d`, pas de `sed -i` sans argument, pas de `readlink -f`, pas de `grep -P`.
- **Aucune attribution Claude/AI** dans les messages de commit et de PR.
- **Chemins :** état dans `.claude/state/` (gitignoré), mémoire dans `.claude/memory/` (committée).
- Chaque tâche se termine par un commit sur la branche `feat/sessions-and-learning`, créée depuis `main` à jour.

---

### Task 1: Bibliothèque d'état `lib/state.sh`

**Files:**
- Create: `plugins/dev-workflow/scripts/lib/state.sh`
- Create: `plugins/dev-workflow/tests/lib.sh`
- Create: `plugins/dev-workflow/tests/state.test.sh`
- Create: `plugins/dev-workflow/tests/run.sh`
- Modify: `plugins/dev-workflow/tests/hooks.test.sh` (remplacer les helpers locaux par `tests/lib.sh`)

**Interfaces:**
- Consumes: rien (première tâche).
- Produces, toutes sourçables via `. "$SCRIPTS/lib/state.sh"` :
  - `dw_json_get <json-string> <dotted.path>` → valeur scalaire sur stdout, chaîne vide si absente. Retourne `1` si aucun parseur JSON n'est disponible.
  - `dw_branch_slug [dir]` → slug sur stdout, toujours non vide.
  - `dw_state_dir [dir]` → `<dir>/.claude/state`
  - `dw_progress_file [dir]` → `<dir>/.claude/state/progress/<slug>.md`
  - `dw_sessions_dir [dir]` → `<dir>/.claude/state/sessions`
  - `dw_lessons_dir [dir]` → `<dir>/.claude/memory/lessons`
  - `dw_atomic_write <dest>` → lit stdin, écrit `<dest>` atomiquement, retourne `0`/`1`.
  - `dw_now_iso` → `2026-09-14T08:42:11Z`
  - `dw_now_epoch` → entier.
  - `dw_session_alive <fichier-json>` → `0` si vivante, `1` sinon.

- [ ] **Step 1: Écrire les helpers de test partagés**

Créer `plugins/dev-workflow/tests/lib.sh` :

```bash
#!/usr/bin/env bash
# Shared helpers for the plugin's golden-input tests.
# Sourced by every *.test.sh file; never executed on its own.

fail=0

check() { # name expected actual
  if [ "$2" = "$3" ]; then
    echo "PASS $1"
  else
    echo "FAIL $1 expected=$2 got=$3"
    fail=1
  fi
}

check_contains() { # name needle haystack
  case "$3" in
    *"$2"*) echo "PASS $1" ;;
    *) echo "FAIL $1 (missing '$2')"; fail=1 ;;
  esac
}

check_lacks() { # name needle haystack
  case "$3" in
    *"$2"*) echo "FAIL $1 (unexpected '$2')"; fail=1 ;;
    *) echo "PASS $1" ;;
  esac
}

# A throwaway git repo, so branch-dependent tests never touch the real one.
make_repo() { # dir branch
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email t@example.com
  git -C "$1" config user.name Test
  git -C "$1" checkout -q -b "$2"
  echo seed > "$1/seed.txt"
  git -C "$1" add seed.txt
  git -C "$1" commit -q -m "chore: seed"
}

report() { # suite-name
  [ "$fail" -eq 0 ] && echo "ALL TESTS PASSED ($1)" || echo "SOME TESTS FAILED ($1)"
  return "$fail"
}
```

- [ ] **Step 2: Écrire les tests de `lib/state.sh` (ils doivent échouer)**

Créer `plugins/dev-workflow/tests/state.test.sh` :

```bash
#!/usr/bin/env bash
# Tests for scripts/lib/state.sh
set -u

SCRIPTS="$(cd "$(dirname "$0")/../scripts" && pwd)"
. "$(dirname "$0")/lib.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

bash -n "$SCRIPTS/lib/state.sh" || fail=1
. "$SCRIPTS/lib/state.sh"

# --- dw_json_get ---
json='{"session_id":"abc-123","cwd":"/tmp/x","tool_input":{"command":"git status"}}'
check json-scalar   "abc-123"    "$(dw_json_get "$json" session_id)"
check json-nested   "git status" "$(dw_json_get "$json" tool_input.command)"
check json-missing  ""           "$(dw_json_get "$json" nope.nothing)"
check json-garbage  ""           "$(dw_json_get 'not json' session_id)"

# --- dw_branch_slug ---
make_repo "$WORK/plain" main
check slug-plain "main" "$(dw_branch_slug "$WORK/plain")"

make_repo "$WORK/slashes" feat/my-thing
check slug-slash "feat-my-thing" "$(dw_branch_slug "$WORK/slashes")"

make_repo "$WORK/exotic" "feat/Ét@rangé  x"
check slug-exotic "feat-t-rang-x" "$(dw_branch_slug "$WORK/exotic")"

sha=$(git -C "$WORK/plain" rev-parse --short=7 HEAD)
git -C "$WORK/plain" checkout -q --detach HEAD
check slug-detached "detached-$sha" "$(dw_branch_slug "$WORK/plain")"

mkdir -p "$WORK/nogit"
check slug-nogit "no-branch" "$(dw_branch_slug "$WORK/nogit")"

# --- paths ---
check path-progress "$WORK/plain/.claude/state/progress/detached-$sha.md" "$(dw_progress_file "$WORK/plain")"
check path-sessions "$WORK/nogit/.claude/state/sessions" "$(dw_sessions_dir "$WORK/nogit")"
check path-lessons  "$WORK/nogit/.claude/memory/lessons" "$(dw_lessons_dir "$WORK/nogit")"

# --- dw_atomic_write ---
dest="$WORK/deep/nested/out.txt"
printf 'hello\n' | dw_atomic_write "$dest"
check atomic-content "hello" "$(cat "$dest")"
check atomic-no-temp "0" "$(find "$WORK/deep/nested" -name '.dw.*' | wc -l | tr -d ' ')"

# --- timestamps ---
case "$(dw_now_iso)" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) echo "PASS iso-shape" ;;
  *) echo "FAIL iso-shape got=$(dw_now_iso)"; fail=1 ;;
esac
case "$(dw_now_epoch)" in
  ''|*[!0-9]*) echo "FAIL epoch-numeric"; fail=1 ;;
  *) echo "PASS epoch-numeric" ;;
esac

# --- dw_session_alive ---
sess="$WORK/sessions"; mkdir -p "$sess"
now=$(dw_now_epoch)
printf '{"session_id":"live","pid":%s,"branch":"main","cwd":"/tmp","started_at_epoch":%s,"last_seen_epoch":%s}\n' \
  "$$" "$now" "$now" > "$sess/live.json"
dw_session_alive "$sess/live.json" && echo "PASS alive-self" || { echo "FAIL alive-self"; fail=1; }

# A pid that cannot exist.
printf '{"session_id":"dead","pid":4194303,"branch":"main","cwd":"/tmp","started_at_epoch":%s,"last_seen_epoch":%s}\n' \
  "$now" "$now" > "$sess/dead.json"
dw_session_alive "$sess/dead.json" && { echo "FAIL alive-dead-pid"; fail=1; } || echo "PASS alive-dead-pid"

# Live pid, but untouched for more than 24h -> stale (pid reuse guard).
old=$((now - 90000))
printf '{"session_id":"old","pid":%s,"branch":"main","cwd":"/tmp","started_at_epoch":%s,"last_seen_epoch":%s}\n' \
  "$$" "$old" "$old" > "$sess/old.json"
dw_session_alive "$sess/old.json" && { echo "FAIL alive-ttl"; fail=1; } || echo "PASS alive-ttl"

# Live pid, idle for 3h -> still alive (the pid is what matters).
idle=$((now - 10800))
printf '{"session_id":"idle","pid":%s,"branch":"main","cwd":"/tmp","started_at_epoch":%s,"last_seen_epoch":%s}\n' \
  "$$" "$idle" "$idle" > "$sess/idle.json"
dw_session_alive "$sess/idle.json" && echo "PASS alive-idle" || { echo "FAIL alive-idle"; fail=1; }

check_lacks malformed-quiet "Traceback" "$(printf 'garbage' > "$sess/bad.json"; dw_session_alive "$sess/bad.json" 2>&1)"

report state
```

- [ ] **Step 3: Lancer les tests pour vérifier qu'ils échouent**

Run: `bash plugins/dev-workflow/tests/state.test.sh`
Expected: FAIL — `scripts/lib/state.sh` n'existe pas (`bash -n` échoue, puis le `.` échoue).

- [ ] **Step 4: Écrire `lib/state.sh`**

Créer `plugins/dev-workflow/scripts/lib/state.sh` :

```bash
#!/usr/bin/env bash
# Shared state helpers for the dev-workflow hooks.
# Sourced, never executed. No function here writes to stdout except to return
# its value: hook stdout is injected into the model's context.

DW_SESSION_TTL=${DW_SESSION_TTL:-86400}   # pid-reuse guard, not an idle timeout

dw_json_get() { # <json-string> <dotted.path>
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r --arg p "$2" \
      'try getpath($p | split(".")) // empty | if type=="string" then . else tojson end' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    for k in sys.argv[1].split("."):
        d = d[k]
    print(d if isinstance(d, str) else json.dumps(d))
except Exception:
    pass
' "$2" 2>/dev/null
  elif command -v python >/dev/null 2>&1; then
    printf '%s' "$1" | python -c '
import json, sys
try:
    d = json.load(sys.stdin)
    for k in sys.argv[1].split("."):
        d = d[k]
    print(d if isinstance(d, str) else json.dumps(d))
except Exception:
    pass
' "$2" 2>/dev/null
  else
    return 1
  fi
}

dw_branch_slug() { # [dir]
  dw__dir=${1:-${CLAUDE_PROJECT_DIR:-$PWD}}
  if ! git -C "$dw__dir" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'no-branch'
    return 0
  fi
  dw__b=$(git -C "$dw__dir" branch --show-current 2>/dev/null)
  if [ -z "$dw__b" ]; then
    dw__sha=$(git -C "$dw__dir" rev-parse --short=7 HEAD 2>/dev/null) || dw__sha=unknown
    printf 'detached-%s' "$dw__sha"
    return 0
  fi
  printf '%s' "$dw__b" \
    | LC_ALL=C sed -e 's#/#-#g' -e 's#[^A-Za-z0-9._-]#-#g' -e 's#--*#-#g' -e 's#^-##' -e 's#-$##' \
    | cut -c1-80
}

dw_state_dir()    { printf '%s/.claude/state' "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"; }
dw_sessions_dir() { printf '%s/sessions' "$(dw_state_dir "${1:-}")"; }
dw_lessons_dir()  { printf '%s/.claude/memory/lessons' "${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"; }

dw_progress_file() { # [dir]
  dw__d=${1:-${CLAUDE_PROJECT_DIR:-$PWD}}
  printf '%s/progress/%s.md' "$(dw_state_dir "$dw__d")" "$(dw_branch_slug "$dw__d")"
}

dw_atomic_write() { # <dest>, content on stdin
  dw__dest=$1
  dw__dir=$(dirname "$dw__dest")
  mkdir -p "$dw__dir" 2>/dev/null || return 1
  dw__tmp=$(mktemp "$dw__dir/.dw.XXXXXX") || return 1
  if cat > "$dw__tmp" && mv -f "$dw__tmp" "$dw__dest"; then
    return 0
  fi
  rm -f "$dw__tmp" 2>/dev/null
  return 1
}

dw_now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
dw_now_epoch() { date +%s; }

# A session is alive when its pid still answers. The TTL only guards against a
# pid being reused after a reboot -- an open but idle session must survive.
dw_session_alive() { # <session-json-file>
  [ -f "$1" ] || return 1
  dw__json=$(cat "$1" 2>/dev/null) || return 1
  dw__pid=$(dw_json_get "$dw__json" pid)
  dw__seen=$(dw_json_get "$dw__json" last_seen_epoch)
  case "$dw__pid" in ''|*[!0-9]*) return 1 ;; esac
  case "$dw__seen" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$dw__pid" 2>/dev/null || return 1
  [ $(( $(dw_now_epoch) - dw__seen )) -lt "$DW_SESSION_TTL" ] || return 1
  return 0
}
```

- [ ] **Step 5: Lancer les tests jusqu'au vert**

Run: `bash plugins/dev-workflow/tests/state.test.sh`
Expected: `ALL TESTS PASSED (state)`

Si `slug-exotic` échoue, comparer le résultat obtenu à l'attendu `feat-t-rang-x` et ajuster **le test**, pas la fonction : l'important est que le slug soit déterministe et sûr pour un nom de fichier, pas sa valeur exacte sur un cas tordu.

- [ ] **Step 6: Créer le lanceur et rebrancher les tests existants**

Créer `plugins/dev-workflow/tests/run.sh` :

```bash
#!/usr/bin/env bash
# Runs every test suite; exits non-zero if any of them fails.
# Run: bash plugins/dev-workflow/tests/run.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
rc=0
for suite in "$here"/*.test.sh; do
  echo "--- $(basename "$suite") ---"
  bash "$suite" || rc=1
done
[ "$rc" -eq 0 ] && echo "=== ALL SUITES PASSED ===" || echo "=== SOME SUITES FAILED ==="
exit $rc
```

Dans `plugins/dev-workflow/tests/hooks.test.sh`, supprimer la déclaration locale de `fail=0` et de la fonction `check`, et les remplacer — juste après la ligne `SCRIPTS=...` — par :

```bash
. "$(dirname "$0")/lib.sh"
```

Puis remplacer la dernière ligne `[ "$fail" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"` et le `exit $fail` qui la suit par :

```bash
report hooks
```

- [ ] **Step 7: Vérifier que l'ancienne suite reste verte**

Run: `bash plugins/dev-workflow/tests/run.sh`
Expected: les deux suites passent, `=== ALL SUITES PASSED ===`

- [ ] **Step 8: Commit**

```bash
git add plugins/dev-workflow/scripts/lib/state.sh plugins/dev-workflow/tests/
git commit -m "feat(dev-workflow): shared state helpers for branch-scoped session state"
```

---

### Task 2: Registre des sessions et injection au démarrage

**Files:**
- Modify: `plugins/dev-workflow/scripts/session-context.sh` (refonte complète)
- Create: `plugins/dev-workflow/tests/session.test.sh`

**Interfaces:**
- Consumes: toutes les fonctions de `lib/state.sh` (Task 1).
- Produces :
  - Le format d'entrée de registre `<sessions_dir>/<session_id>.json`, avec les clés `session_id`, `pid`, `branch`, `cwd`, `started_at`, `started_at_epoch`, `last_seen`, `last_seen_epoch`. Task 3 (`session-end.sh`, heartbeat) en dépend.
  - La fonction `dw_register_session <json-stdin>` n'est **pas** exportée : tout tient dans `session-context.sh`.

- [ ] **Step 1: Écrire les tests (ils doivent échouer)**

Créer `plugins/dev-workflow/tests/session.test.sh` :

```bash
#!/usr/bin/env bash
# Tests for session-context.sh: registry, collisions, staleness, injection.
set -u

SCRIPTS="$(cd "$(dirname "$0")/../scripts" && pwd)"
. "$(dirname "$0")/lib.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

bash -n "$SCRIPTS/session-context.sh" || fail=1

REPO="$WORK/repo"
make_repo "$REPO" feat/alpha

run_start() { # session_id -> stdout of the hook
  printf '{"session_id":"%s","cwd":"%s","source":"startup","hook_event_name":"SessionStart"}' "$1" "$REPO" \
    | CLAUDE_PROJECT_DIR="$REPO" bash "$SCRIPTS/session-context.sh" 2>/dev/null
}

# --- registration ---
out=$(run_start sess-one)
check registry-written 1 "$(ls "$REPO/.claude/state/sessions" | wc -l | tr -d ' ')"
check_contains registry-branch '"branch": "feat/alpha"' "$(cat "$REPO/.claude/state/sessions/sess-one.json")"
check_contains policy-injected "Standing policy" "$out"

# --- no collision banner when alone ---
check_lacks alone-no-collision "another session" "$out"

# --- collision on the SAME branch ---
now=$(date +%s)
printf '{"session_id":"other","pid":%s,"branch":"feat/alpha","cwd":"%s","started_at":"x","started_at_epoch":%s,"last_seen":"x","last_seen_epoch":%s}\n' \
  "$$" "$REPO" "$now" "$now" > "$REPO/.claude/state/sessions/other.json"
out=$(run_start sess-two)
check_contains collision-same-branch "feat/alpha" "$out"
check_contains collision-warned "another session" "$out"

# --- a session on a DIFFERENT branch is informational, not a warning ---
rm -f "$REPO/.claude/state/sessions/other.json"
printf '{"session_id":"elsewhere","pid":%s,"branch":"feat/beta","cwd":"%s","started_at":"x","started_at_epoch":%s,"last_seen":"x","last_seen_epoch":%s}\n' \
  "$$" "$REPO" "$now" "$now" > "$REPO/.claude/state/sessions/elsewhere.json"
out=$(run_start sess-three)
check_contains other-branch-listed "feat/beta" "$out"
check_lacks other-branch-not-warned "may be overwritten" "$out"

# --- dead sessions are purged ---
printf '{"session_id":"ghost","pid":4194303,"branch":"feat/alpha","cwd":"%s","started_at":"x","started_at_epoch":%s,"last_seen":"x","last_seen_epoch":%s}\n' \
  "$REPO" "$now" "$now" > "$REPO/.claude/state/sessions/ghost.json"
run_start sess-four >/dev/null
[ -f "$REPO/.claude/state/sessions/ghost.json" ] && { echo "FAIL ghost-purged"; fail=1; } || echo "PASS ghost-purged"

# --- progress file of the CURRENT branch is injected, others are not ---
mkdir -p "$REPO/.claude/state/progress"
printf '# Progress\n**Updated:** 2026-09-14 08:00\n**Branch:** feat/alpha\n\nALPHA-MARKER\n' \
  > "$REPO/.claude/state/progress/feat-alpha.md"
printf '# Progress\nBETA-MARKER\n' > "$REPO/.claude/state/progress/feat-beta.md"
out=$(run_start sess-five)
check_contains progress-current "ALPHA-MARKER" "$out"
check_lacks progress-other "BETA-MARKER" "$out"

# --- staleness: a commit made after "Updated:" raises the banner ---
echo change > "$REPO/later.txt"
git -C "$REPO" add later.txt
git -C "$REPO" commit -q -m "chore: later"
out=$(run_start sess-six)
check_contains stale-banner "may be out of date" "$out"

# --- fresh progress (updated after the last commit) raises nothing ---
printf '# Progress\n**Updated:** 2099-01-01 00:00\n**Branch:** feat/alpha\n\nALPHA-MARKER\n' \
  > "$REPO/.claude/state/progress/feat-alpha.md"
out=$(run_start sess-seven)
check_lacks fresh-no-banner "may be out of date" "$out"

# --- legacy .claude/PROGRESS.md is still read, with a migration notice ---
LEG="$WORK/legacy"
make_repo "$LEG" main
mkdir -p "$LEG/.claude"
printf '# Progress\nLEGACY-MARKER\n' > "$LEG/.claude/PROGRESS.md"
out=$(printf '{"session_id":"leg","cwd":"%s","source":"startup"}' "$LEG" \
  | CLAUDE_PROJECT_DIR="$LEG" bash "$SCRIPTS/session-context.sh" 2>/dev/null)
check_contains legacy-read "LEGACY-MARKER" "$out"
check_contains legacy-notice "/dev-workflow:setup" "$out"

# --- never fails, even outside a git repo with no .claude at all ---
mkdir -p "$WORK/bare"
printf '{"session_id":"bare","cwd":"%s","source":"startup"}' "$WORK/bare" \
  | CLAUDE_PROJECT_DIR="$WORK/bare" bash "$SCRIPTS/session-context.sh" >/dev/null 2>&1
check bare-exit-zero 0 "$?"

# --- malformed stdin must not crash the hook ---
printf 'not json' | CLAUDE_PROJECT_DIR="$REPO" bash "$SCRIPTS/session-context.sh" >/dev/null 2>&1
check malformed-exit-zero 0 "$?"

report session
```

- [ ] **Step 2: Lancer pour voir l'échec**

Run: `bash plugins/dev-workflow/tests/session.test.sh`
Expected: FAIL — aucun registre écrit, aucun bandeau (le script actuel ne fait qu'injecter).

- [ ] **Step 3: Réécrire `session-context.sh`**

Remplacer intégralement `plugins/dev-workflow/scripts/session-context.sh` par :

```bash
#!/usr/bin/env bash
# SessionStart hook: register this session, warn about parallel sessions on the
# same branch, and inject the standing policy, the branch's progress file, the
# memory index and the active lesson titles.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/state.sh"

input=$(cat 2>/dev/null || true)
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
session_id=$(dw_json_get "$input" session_id 2>/dev/null)
[ -n "$session_id" ] || session_id="unknown-$$"

branch=$(git -C "$dir" branch --show-current 2>/dev/null)
[ -n "$branch" ] || branch="(no branch)"
slug=$(dw_branch_slug "$dir")
sessions=$(dw_sessions_dir "$dir")
progress=$(dw_progress_file "$dir")
legacy="$dir/.claude/PROGRESS.md"
index="$dir/.claude/memory/INDEX.md"
lessons=$(dw_lessons_dir "$dir")

mkdir -p "$sessions" 2>/dev/null || true

# --- purge dead sessions, then collect the live ones ---
same_branch=""
other_branches=""
for f in "$sessions"/*.json; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in "$session_id.json") continue ;; esac
  if ! dw_session_alive "$f"; then
    rm -f "$f" 2>/dev/null
    continue
  fi
  j=$(cat "$f" 2>/dev/null)
  b=$(dw_json_get "$j" branch)
  started=$(dw_json_get "$j" started_at_epoch)
  case "$started" in ''|*[!0-9]*) started=$(dw_now_epoch) ;; esac
  age=$(( ($(dw_now_epoch) - started) / 60 ))
  if [ "$b" = "$branch" ]; then
    same_branch="$same_branch$b|$age|$(dw_json_get "$j" cwd)
"
  else
    other_branches="$other_branches$b "
  fi
done

# --- register this session ---
now_iso=$(dw_now_iso); now_epoch=$(dw_now_epoch)
printf '{\n  "session_id": "%s",\n  "pid": %s,\n  "branch": "%s",\n  "cwd": "%s",\n  "started_at": "%s",\n  "started_at_epoch": %s,\n  "last_seen": "%s",\n  "last_seen_epoch": %s\n}\n' \
  "$session_id" "$PPID" "$branch" "$dir" "$now_iso" "$now_epoch" "$now_iso" "$now_epoch" \
  | dw_atomic_write "$sessions/$session_id.json" 2>/dev/null || true

echo "<dev-workflow-context>"
cat <<'POLICY'
== Standing policy (dev-workflow plugin) — apply WITHOUT being asked ==
- Before researching any library/API/error/codebase question: invoke skill dev-workflow:project-memory (reuse .claude/memory/ entries; save findings after).
- When writing or refactoring code: invoke skill dev-workflow:coding-rules first.
- When starting a feature/fix/chore, or committing/pushing/opening a PR: invoke skill dev-workflow:feature-workflow (dedicated branch, Conventional Commits, draft PR, never any Claude/AI attribution).
- For bulky exploration/research or a well-specified implementation chunk: invoke skill dev-workflow:orchestrate and delegate to the researcher (haiku) / coder (opus) / reviewer (opus) / browser-tester (sonnet, Playwright) subagents.
- Before marking a UI-touching PR ready: delegate Playwright browser tests to the browser-tester subagent (sonnet); unit tests alone are not enough for user-facing flows.
- At every milestone, before compaction, and at session end: invoke skill dev-workflow:session-handoff to update the branch's progress file under .claude/state/progress/.
- When the same mistake shows up twice: invoke skill dev-workflow:learn to write it down as a lesson under .claude/memory/lessons/.
POLICY

if [ -n "$same_branch" ]; then
  echo ""
  echo "== WARNING: another session is active on this same branch ($branch) =="
  printf '%s' "$same_branch" | while IFS='|' read -r b age cwd; do
    [ -n "$b" ] && echo "- started ${age}m ago in $cwd"
  done
  echo "Its progress file is the same as yours and may be overwritten. Coordinate, or move to your own branch."
fi
if [ -n "$other_branches" ]; then
  echo ""
  echo "== Other live dev-workflow sessions, on other branches: $other_branches=="
fi

progress_shown=""
if [ -f "$progress" ]; then
  echo ""
  echo "== Session progress ($progress) — resume from here instead of re-exploring =="
  cat "$progress"
  progress_shown="$progress"
elif [ -f "$legacy" ]; then
  echo ""
  echo "== Session progress (.claude/PROGRESS.md, LEGACY PATH) — resume from here instead of re-exploring =="
  cat "$legacy"
  echo ""
  echo "NOTE: progress files are now per-branch under .claude/state/progress/. Run /dev-workflow:setup once to migrate this file."
  progress_shown="$legacy"
fi

# --- staleness: commits landed after the progress file was last updated ---
if [ -n "$progress_shown" ] && git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  updated=$(grep -m1 '^\*\*Updated:\*\*' "$progress_shown" 2>/dev/null | sed -E 's/^\*\*Updated:\*\*[[:space:]]*//')
  if [ -n "$updated" ]; then
    behind=$(git -C "$dir" rev-list --count --since="$updated" HEAD 2>/dev/null)
    case "$behind" in ''|*[!0-9]*) behind=0 ;; esac
    if [ "$behind" -gt 0 ]; then
      echo ""
      echo "== This progress file may be out of date: $behind commit(s) landed on $branch after $updated. Verify before resuming. =="
    fi
  fi
fi

if [ -f "$index" ]; then
  echo ""
  echo "== Project memory index (.claude/memory/INDEX.md) — check for an existing entry before any new research =="
  cat "$index"
fi

if [ -d "$lessons" ]; then
  titles=$(grep -h -m1 '^rule:' "$lessons"/*.md 2>/dev/null | sed -E 's/^rule:[[:space:]]*//')
  if [ -n "$titles" ]; then
    total=$(printf '%s\n' "$titles" | wc -l | tr -d ' ')
    echo ""
    echo "== Lessons learned ($total) — do not repeat these; the full text is injected when it becomes relevant =="
    printf '%s\n' "$titles" | head -15 | sed 's/^/- /'
    [ "$total" -gt 15 ] && echo "- (+$((total - 15)) more in .claude/memory/lessons/)"
  fi
fi

if [ ! -f "$progress" ] && [ ! -f "$legacy" ] && [ ! -d "$dir/.claude/memory" ]; then
  echo ""
  echo "== Project not initialized for dev-workflow: suggest running /dev-workflow:setup once (creates .claude/memory/ and .claude/state/). =="
fi
echo "</dev-workflow-context>"
exit 0
```

- [ ] **Step 4: Lancer les tests jusqu'au vert**

Run: `bash plugins/dev-workflow/tests/run.sh`
Expected: les trois suites passent.

- [ ] **Step 5: Commit**

```bash
git add plugins/dev-workflow/scripts/session-context.sh plugins/dev-workflow/tests/session.test.sh
git commit -m "feat(dev-workflow): branch-scoped progress and live-session registry at startup"
```

---

### Task 3: Fin de session, heartbeat, et câblage des hooks

**Files:**
- Create: `plugins/dev-workflow/scripts/session-end.sh`
- Modify: `plugins/dev-workflow/scripts/prompt-reminder.sh`
- Modify: `plugins/dev-workflow/scripts/precompact-reminder.sh`
- Modify: `plugins/dev-workflow/hooks/hooks.json`
- Modify: `plugins/dev-workflow/tests/session.test.sh` (ajouts en fin de fichier, avant `report session`)

**Interfaces:**
- Consumes: le format d'entrée de registre et `lib/state.sh` (Tasks 1-2).
- Produces: rien de nouveau pour les tâches suivantes.

- [ ] **Step 1: Écrire les tests (ils doivent échouer)**

Dans `plugins/dev-workflow/tests/session.test.sh`, **avant** la ligne `report session`, insérer :

```bash
# --- session-end.sh removes the registry entry ---
bash -n "$SCRIPTS/session-end.sh" || fail=1
run_start sess-end >/dev/null
[ -f "$REPO/.claude/state/sessions/sess-end.json" ] || { echo "FAIL end-precondition"; fail=1; }
printf '{"session_id":"sess-end","cwd":"%s","reason":"clear"}' "$REPO" \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$SCRIPTS/session-end.sh" >/dev/null 2>&1
[ -f "$REPO/.claude/state/sessions/sess-end.json" ] && { echo "FAIL end-removed"; fail=1; } || echo "PASS end-removed"

# it must not touch other sessions
run_start sess-keep >/dev/null
printf '{"session_id":"sess-end","cwd":"%s","reason":"clear"}' "$REPO" \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$SCRIPTS/session-end.sh" >/dev/null 2>&1
[ -f "$REPO/.claude/state/sessions/sess-keep.json" ] && echo "PASS end-keeps-others" || { echo "FAIL end-keeps-others"; fail=1; }

# unknown session id is a no-op, never an error
printf '{"session_id":"never-existed","cwd":"%s","reason":"other"}' "$REPO" \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$SCRIPTS/session-end.sh" >/dev/null 2>&1
check end-unknown-exit-zero 0 "$?"

# --- heartbeat: prompt-reminder refreshes last_seen ---
export XDG_CACHE_HOME="$WORK/cache"
run_start sess-beat >/dev/null
before=$(grep -o '"last_seen_epoch": [0-9]*' "$REPO/.claude/state/sessions/sess-beat.json" | grep -o '[0-9]*')
sleep 1
printf '{"session_id":"sess-beat","cwd":"%s","prompt":"hello"}' "$REPO" \
  | CLAUDE_PROJECT_DIR="$REPO" bash "$SCRIPTS/prompt-reminder.sh" >/dev/null 2>&1
after=$(grep -o '"last_seen_epoch": [0-9]*' "$REPO/.claude/state/sessions/sess-beat.json" | grep -o '[0-9]*')
[ "$after" -gt "$before" ] && echo "PASS heartbeat-refreshed" || { echo "FAIL heartbeat-refreshed before=$before after=$after"; fail=1; }

# --- throttle is keyed per branch, not per project ---
rm -rf "$WORK/cache"
o1=$(printf '{"session_id":"s","cwd":"%s","prompt":"x"}' "$REPO" | CLAUDE_PROJECT_DIR="$REPO" bash "$SCRIPTS/prompt-reminder.sh" 2>/dev/null)
o2=$(printf '{"session_id":"s","cwd":"%s","prompt":"x"}' "$REPO" | CLAUDE_PROJECT_DIR="$REPO" bash "$SCRIPTS/prompt-reminder.sh" 2>/dev/null)
[ -n "$o1" ] && echo "PASS throttle-first" || { echo "FAIL throttle-first"; fail=1; }
[ -z "$o2" ] && echo "PASS throttle-second" || { echo "FAIL throttle-second"; fail=1; }
git -C "$REPO" checkout -q -b feat/gamma
o3=$(printf '{"session_id":"s","cwd":"%s","prompt":"x"}' "$REPO" | CLAUDE_PROJECT_DIR="$REPO" bash "$SCRIPTS/prompt-reminder.sh" 2>/dev/null)
[ -n "$o3" ] && echo "PASS throttle-per-branch" || { echo "FAIL throttle-per-branch"; fail=1; }
git -C "$REPO" checkout -q feat/alpha
```

- [ ] **Step 2: Lancer pour voir l'échec**

Run: `bash plugins/dev-workflow/tests/session.test.sh`
Expected: FAIL — `session-end.sh` n'existe pas, le heartbeat n'est pas écrit.

- [ ] **Step 3: Écrire `session-end.sh`**

Créer `plugins/dev-workflow/scripts/session-end.sh` :

```bash
#!/usr/bin/env bash
# SessionEnd hook: drop this session's registry entry so parallel-session
# warnings stay accurate. Optimistic by design -- the doc does not guarantee
# this hook runs when the process is killed, so SessionStart's pid-based purge
# remains the real guarantee.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/state.sh"

input=$(cat 2>/dev/null || true)
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
session_id=$(dw_json_get "$input" session_id 2>/dev/null)

[ -n "$session_id" ] || exit 0
case "$session_id" in */*|..|.) exit 0 ;; esac   # never let an id escape the directory

rm -f "$(dw_sessions_dir "$dir")/$session_id.json" 2>/dev/null || true
exit 0
```

- [ ] **Step 4: Ajouter le heartbeat et la clé de branche à `prompt-reminder.sh`**

Dans `plugins/dev-workflow/scripts/prompt-reminder.sh`, remplacer le bloc allant de `THROTTLE_SECONDS=1800` jusqu'à la ligne `stamp_file="$stamp_dir/reminder-$key"` incluse par :

```bash
THROTTLE_SECONDS=1800

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/state.sh"

input=$(cat 2>/dev/null || true)
project="${CLAUDE_PROJECT_DIR:-$PWD}"
slug=$(dw_branch_slug "$project")

# Heartbeat: keep this session's registry entry fresh so other sessions can see it.
session_id=$(dw_json_get "$input" session_id 2>/dev/null)
if [ -n "$session_id" ]; then
  entry="$(dw_sessions_dir "$project")/$session_id.json"
  if [ -f "$entry" ]; then
    now_iso=$(dw_now_iso); now_epoch=$(dw_now_epoch)
    sed -e "s/\"last_seen\": \"[^\"]*\"/\"last_seen\": \"$now_iso\"/" \
        -e "s/\"last_seen_epoch\": [0-9]*/\"last_seen_epoch\": $now_epoch/" \
        "$entry" 2>/dev/null | dw_atomic_write "$entry" 2>/dev/null || true
  fi
fi

# Throttle is keyed per project AND branch, so two branches don't silence each other.
key=$(printf '%s@%s' "$project" "$slug" | cksum | cut -d' ' -f1)
stamp_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-dev-workflow"
stamp_file="$stamp_dir/reminder-$key"
```

Mettre à jour le commentaire d'en-tête du fichier : le timbre est désormais *« keyed by a hash of the project path and the current branch »*.

- [ ] **Step 5: Mettre `precompact-reminder.sh` au nouveau chemin**

Dans `plugins/dev-workflow/scripts/precompact-reminder.sh`, remplacer le calcul de `key` et le message final par :

```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/state.sh"

project="${CLAUDE_PROJECT_DIR:-$PWD}"
key=$(printf '%s@%s' "$project" "$(dw_branch_slug "$project")" | cksum | cut -d' ' -f1)
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/claude-dev-workflow/reminder-$key" 2>/dev/null || true

echo "dev-workflow: context is about to be compacted. Update this branch's progress file at $(dw_progress_file "$project") NOW (current task, done, next concrete step, open questions) so nothing is lost. Anything that must survive beyond this branch — a trap, a rule learned the hard way — belongs in a lesson: invoke skill dev-workflow:learn."
```

- [ ] **Step 6: Câbler les nouveaux hooks**

Remplacer `plugins/dev-workflow/hooks/hooks.json` par :

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/session-context.sh\"",
            "statusMessage": "Loading project progress, memory and lessons"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/session-end.sh\""
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/prompt-reminder.sh\""
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/guard-commit.sh\""
          }
        ]
      },
      {
        "matcher": "Bash|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/lesson-guard.sh\""
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}/scripts/precompact-reminder.sh\""
          }
        ]
      }
    ]
  }
}
```

`lesson-guard.sh` est créé en Task 5 ; d'ici là le hook pointe vers un fichier absent, ce qui est sans effet sur les tests (qui appellent les scripts directement) mais **doit** être suivi de Task 5 avant toute utilisation réelle du plugin.

- [ ] **Step 7: Lancer les tests jusqu'au vert**

Run: `bash plugins/dev-workflow/tests/run.sh`
Expected: toutes les suites passent, y compris les tests historiques de throttle de `hooks.test.sh`.

Attention : `hooks.test.sh` appelle `prompt-reminder.sh` **sans** JSON sur stdin. Le script doit continuer de fonctionner dans ce cas — c'est ce que garantit `input=$(cat 2>/dev/null || true)` suivi d'un `session_id` vide. Si ces tests bloquent en attente d'entrée, rediriger `</dev/null` dans `hooks.test.sh`.

- [ ] **Step 8: Commit**

```bash
git add plugins/dev-workflow/scripts/ plugins/dev-workflow/hooks/hooks.json plugins/dev-workflow/tests/
git commit -m "feat(dev-workflow): session-end cleanup, heartbeat, branch-keyed throttle"
```

---

### Task 4: Index mémoire régénéré et répertoire des leçons

**Files:**
- Create: `plugins/dev-workflow/scripts/memory-index.sh`
- Create: `plugins/dev-workflow/tests/memory.test.sh`

**Interfaces:**
- Consumes: `lib/state.sh` (Task 1).
- Produces: le **format de frontmatter des leçons**, dont Task 5 dépend — clés plates `rule`, `why`, `tools`, `pattern`, `level`, `hits`, `overrides`, `last_hit`.

- [ ] **Step 1: Écrire les tests (ils doivent échouer)**

Créer `plugins/dev-workflow/tests/memory.test.sh` :

```bash
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

report memory
```

- [ ] **Step 2: Lancer pour voir l'échec**

Run: `bash plugins/dev-workflow/tests/memory.test.sh`
Expected: FAIL — `memory-index.sh` n'existe pas.

- [ ] **Step 3: Écrire `memory-index.sh`**

Créer `plugins/dev-workflow/scripts/memory-index.sh` :

```bash
#!/usr/bin/env bash
# Regenerate .claude/memory/INDEX.md from the frontmatter of research/ and
# lessons/ entries. Hand-editing the index loses entries whenever two sessions
# write it at once; generating it removes that failure mode entirely.
# Run: plugins/dev-workflow/scripts/memory-index.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/state.sh"

dir="${CLAUDE_PROJECT_DIR:-$PWD}"
mem="$dir/.claude/memory"
[ -d "$mem" ] || exit 0

# Read one flat frontmatter key from a file; empty if absent.
fm() { # <file> <key>
  sed -n '2,/^---$/p' "$1" 2>/dev/null \
    | grep -m1 "^$2:" \
    | sed -E "s/^$2:[[:space:]]*//; s/^\"(.*)\"$/\1/"
}

first_heading() { grep -m1 '^# ' "$1" 2>/dev/null | sed 's/^# //'; }
first_prose()   { grep -m1 -v -e '^$' -e '^#' -e '^---' "$1" 2>/dev/null | cut -c1-120; }

{
  echo "# Project Memory Index"
  echo "Generated by plugins/dev-workflow/scripts/memory-index.sh — do not edit by hand."
  echo ""
  echo "## Research"
  echo "One line per entry: - [topic](research/<file>.md) — one-line answer (YYYY-MM-DD)"
  echo ""
  for f in "$mem"/research/*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    topic=$(fm "$f" topic);  [ -n "$topic" ]  || topic=$(first_heading "$f");  [ -n "$topic" ]  || topic="$base"
    answer=$(fm "$f" answer); [ -n "$answer" ] || answer=$(first_prose "$f")
    date=$(fm "$f" date)
    if [ -n "$date" ]; then
      echo "- [$topic](research/$base) — $answer ($date)"
    else
      echo "- [$topic](research/$base) — $answer"
    fi
  done | LC_ALL=C sort

  echo ""
  echo "## Lessons"
  echo "Mistakes already paid for. Level 2 is injected on a matching action; level 3 blocks it."
  echo ""
  for f in "$mem"/lessons/*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    rule=$(fm "$f" rule); [ -n "$rule" ] || rule=$(first_heading "$f"); [ -n "$rule" ] || continue
    level=$(fm "$f" level); [ -n "$level" ] || level=1
    hits=$(fm "$f" hits);   [ -n "$hits" ]  || hits=0
    echo "- [L$level, ${hits} hit(s)] [$rule](lessons/$base)"
  done | LC_ALL=C sort
} | dw_atomic_write "$mem/INDEX.md"

exit 0
```

- [ ] **Step 4: Lancer les tests jusqu'au vert**

Run: `bash plugins/dev-workflow/tests/memory.test.sh`
Expected: `ALL TESTS PASSED (memory)`

- [ ] **Step 5: Commit**

```bash
git add plugins/dev-workflow/scripts/memory-index.sh plugins/dev-workflow/tests/memory.test.sh
git commit -m "feat(dev-workflow): generate the memory index instead of hand-editing it"
```

---

### Task 5: Garde-fou des leçons

**Files:**
- Create: `plugins/dev-workflow/scripts/lesson-guard.sh`
- Create: `plugins/dev-workflow/tests/lessons.test.sh`

**Interfaces:**
- Consumes: `lib/state.sh` (Task 1) et le format de frontmatter de leçon (Task 4).
- Produces: la convention d'échappatoire `DW_OVERRIDE=<slug>`, documentée par les skills en Task 6.

- [ ] **Step 1: Écrire les tests (ils doivent échouer)**

Créer `plugins/dev-workflow/tests/lessons.test.sh` :

```bash
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
```

- [ ] **Step 2: Lancer pour voir l'échec**

Run: `bash plugins/dev-workflow/tests/lessons.test.sh`
Expected: FAIL — `lesson-guard.sh` n'existe pas.

- [ ] **Step 3: Écrire `lesson-guard.sh`**

Créer `plugins/dev-workflow/scripts/lesson-guard.sh` :

```bash
#!/usr/bin/env bash
# PreToolUse guard (matcher: Bash|Edit|Write): confront the action against the
# lessons in .claude/memory/lessons/. Level 2 surfaces the lesson and allows;
# level 3 blocks (exit 2) and prints the escape hatch. A broken lesson file must
# never stand between the user and their work: anything unexpected exits 0.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/state.sh"

input=$(cat 2>/dev/null || true)
dir="${CLAUDE_PROJECT_DIR:-$PWD}"
lessons=$(dw_lessons_dir "$dir")
[ -d "$lessons" ] || exit 0

tool=$(dw_json_get "$input" tool_name 2>/dev/null)
[ -n "$tool" ] || exit 0

case "$tool" in
  Bash)       subject=$(dw_json_get "$input" tool_input.command) ;;
  Edit|Write) subject=$(dw_json_get "$input" tool_input.file_path) ;;
  *)          exit 0 ;;
esac
[ -n "$subject" ] || exit 0

fm() { # <file> <key>
  sed -n '2,/^---$/p' "$1" 2>/dev/null \
    | grep -m1 "^$2:" \
    | sed -E "s/^$2:[[:space:]]*//; s/^\"(.*)\"$/\1/"
}

bump() { # <file> <key>
  f=$1; k=$2
  cur=$(fm "$f" "$k"); case "$cur" in ''|*[!0-9]*) cur=0 ;; esac
  next=$((cur + 1))
  today=$(date -u +%Y-%m-%d)
  sed -e "s/^$k:.*/$k: $next/" -e "s/^last_hit:.*/last_hit: $today/" "$f" 2>/dev/null \
    | dw_atomic_write "$f" 2>/dev/null || true
}

blocked=0
for f in "$lessons"/*.md; do
  [ -f "$f" ] || continue
  rule=$(fm "$f" rule);       [ -n "$rule" ] || continue
  pattern=$(fm "$f" pattern); [ -n "$pattern" ] || continue
  tools=$(fm "$f" tools);     [ -n "$tools" ] || continue

  # Does this lesson cover the current tool?
  printf '%s' "$tools" | tr ',' '\n' | sed 's/[[:space:]]//g' | grep -qx "$tool" || continue

  # An invalid regex must be ignored, never fatal.
  printf '%s' "$subject" | grep -qE "$pattern" 2>/dev/null || continue

  slug=$(basename "$f" .md)
  level=$(fm "$f" level); case "$level" in ''|*[!0-9]*) level=1 ;; esac
  why=$(fm "$f" why)
  # `1,/^---$/d` deletes from line 1 through the closing `---`, i.e. the whole frontmatter.
  body=$(sed -e '1,/^---$/d' "$f" 2>/dev/null | sed '/^$/d' | head -5)

  if [ "$level" -ge 3 ]; then
    # Escape hatch: DW_OVERRIDE=<slug> as a visible prefix in the command.
    if printf '%s' "$subject" | grep -qE "DW_OVERRIDE=$slug([[:space:];&|]|$)"; then
      bump "$f" overrides
      continue
    fi
    echo "dev-workflow: BLOCKED by lesson '$slug'." >&2
    echo "  Rule: $rule" >&2
    [ -n "$why" ] && echo "  Why:  $why" >&2
    [ -n "$body" ] && echo "$body" | sed 's/^/  /' >&2
    echo "  If this is genuinely the right call, rerun with the prefix: DW_OVERRIDE=$slug <your command>" >&2
    bump "$f" hits
    blocked=1
  elif [ "$level" -eq 2 ]; then
    echo "dev-workflow: lesson '$slug' applies here." >&2
    echo "  Rule: $rule" >&2
    [ -n "$why" ] && echo "  Why:  $why" >&2
    [ -n "$body" ] && echo "$body" | sed 's/^/  /' >&2
    bump "$f" hits
  fi
done

[ "$blocked" -eq 1 ] && exit 2
exit 0
```

- [ ] **Step 4: Lancer les tests jusqu'au vert**

Run: `bash plugins/dev-workflow/tests/lessons.test.sh`
Expected: `ALL TESTS PASSED (lessons)`

Le test `level2-surfaces` capture `2>&1` : le niveau 2 écrit sur **stderr** et sort en `0`. C'est l'idiome déjà utilisé par `guard-commit.sh` pour faire remonter un message sans bloquer, et il est vérifié par le test, pas supposé.

- [ ] **Step 5: Vérifier le niveau 2 dans une vraie session**

Le test prouve que le script écrit sur stderr et sort en `0` ; il ne prouve pas que Claude *voit* ce message. Vérifier en conditions réelles :

1. Créer une leçon de niveau 2 dans le projet courant : `pattern: echo dev-workflow-probe`, `tools: Bash`.
2. Dans une session Claude Code, demander de lancer `echo dev-workflow-probe`.
3. Confirmer que le texte de la leçon apparaît bien dans la conversation.

Si le message **n'apparaît pas**, passer le niveau 2 en `exit 1` (erreur non bloquante, remontée à Claude — c'est ce que fait `guard-commit.sh:35-36` quand il manque un parseur JSON) et ajuster le test `level2-allows` de `0` à `1`. Noter le résultat de cette vérification dans le fichier de spec.

- [ ] **Step 6: Commit**

```bash
git add plugins/dev-workflow/scripts/lesson-guard.sh plugins/dev-workflow/tests/lessons.test.sh
git commit -m "feat(dev-workflow): lesson guard with two-level escalation and escape hatch"
```

---

### Task 6: Skills, agents et documentation

**Files:**
- Create: `plugins/dev-workflow/skills/learn/SKILL.md`
- Modify: `plugins/dev-workflow/skills/session-handoff/SKILL.md`
- Modify: `plugins/dev-workflow/skills/project-memory/SKILL.md`
- Modify: `plugins/dev-workflow/skills/setup/SKILL.md`
- Modify: `plugins/dev-workflow/skills/orchestrate/SKILL.md`
- Modify: `plugins/dev-workflow/agents/coder.md`, `plugins/dev-workflow/agents/reviewer.md`
- Modify: `plugins/dev-workflow/.claude-plugin/plugin.json`
- Modify: `README.md`

**Interfaces:**
- Consumes: tous les chemins et conventions des Tasks 1-5.
- Produces: la documentation utilisateur ; dernière tâche.

- [ ] **Step 1: Écrire la skill `learn`**

Créer `plugins/dev-workflow/skills/learn/SKILL.md` :

```markdown
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

One lesson per file, `.claude/memory/lessons/<kebab-slug>.md`, frontmatter flat (it is parsed on every tool call, by `grep`):

```markdown
---
rule: Never run prisma migrate without --create-only on the dev database
why: "2026-03-12: lost the local seed, 40 minutes gone"
tools: Bash
pattern: prisma migrate
level: 2
hits: 0
overrides: 0
last_hit: 2026-03-12
---

Run it with --create-only, read the generated SQL, then apply.
```

- `rule` — imperative, one line, the thing to do or avoid.
- `why` — the incident that paid for it, dated. A rule without a cost is a preference; it will be ignored.
- `tools` — `Bash`, `Edit`, `Write`, comma-separated. Omit and the lesson stays level 1.
- `pattern` — extended regex (`grep -E`), matched against the Bash command or the edited path. Make it narrow: a pattern that fires on innocent commands trains everyone to ignore lessons.
- `level` — see the ladder below.

Then run `plugins/dev-workflow/scripts/memory-index.sh` to refresh the index. Never edit `INDEX.md` by hand.

## The ladder

| Level | Effect | When |
|---|---|---|
| 1 | Title listed at session start | First write-up, or no reliable pattern |
| 2 | Full lesson surfaced when the pattern matches | Second occurrence |
| 3 | Action **blocked**, escape hatch printed | Third occurrence, or an expensive mistake from the start |

A rule that has to be repeated is a rule that failed. Promoting to level 3 is admitting prose is no longer enough — the same admission `guard-commit.sh` already embodies for Claude attribution.

## Escape hatch and demotion

Level 3 is bypassed with a visible prefix: `DW_OVERRIDE=<slug> <command>`. Each bypass increments `overrides`.

**A lesson that is often overridden is a bad lesson.** At `overrides >= 3`, do not tighten it — fix it: narrow the `pattern`, split it into two lessons, or demote it to level 2. The counter is the feedback loop that keeps this memory honest.

## Deduplicating and retiring

Before writing, read the existing lessons: a near-duplicate must be *edited*, never added alongside — two lessons saying almost the same thing halve the credibility of both. A lesson untriggered for six months moves to `lessons/archive/`, keeping the active set small enough to be read.
```

- [ ] **Step 2: Mettre `session-handoff` au nouveau chemin**

Dans `plugins/dev-workflow/skills/session-handoff/SKILL.md` :

- Remplacer toute mention de `.claude/PROGRESS.md` par `.claude/state/progress/<branch-slug>.md`.
- Après la phrase d'introduction, ajouter :

```markdown
The file is **per branch** (`<branch-slug>` is the current branch with `/` and exotic characters
turned into `-`), so two sessions on two features no longer overwrite each other. If the
SessionStart banner warned that another live session shares your branch, coordinate before
writing — the registry warns, it does not lock.
```

- Dans la section `## Rules`, ajouter :

```markdown
- **A `Watch out` that outlives the branch is a lesson.** Traps tied to this feature stay here and
  die with the branch; a rule that would have saved you on any branch belongs in
  `.claude/memory/lessons/` — invoke `dev-workflow:learn`.
```

- [ ] **Step 3: Documenter les trois mémoires dans `project-memory`**

Dans `plugins/dev-workflow/skills/project-memory/SKILL.md`, ajouter après l'introduction :

```markdown
## Three memories, three purposes

| Directory | Holds | Written by |
|---|---|---|
| `research/` | Facts: library behaviour, API shapes, how this codebase does X | after any non-trivial lookup |
| `decisions.md` | Architectural choices and their rationale | when a choice is made |
| `lessons/` | Mistakes already paid for, with a trigger that can warn or block | `dev-workflow:learn` |

`INDEX.md` is **generated** — run `plugins/dev-workflow/scripts/memory-index.sh` after adding an
entry, and never edit it by hand. Hand-editing is how a concurrent session's entry gets lost.
```

Ajouter aussi le frontmatter attendu d'une entrée de recherche (`topic`, `answer`, `date`), pour que la génération de l'index ait de quoi travailler.

- [ ] **Step 4: Mettre `setup` à jour**

Dans `plugins/dev-workflow/skills/setup/SKILL.md`, remplacer l'étape 1 par :

```markdown
1. **Create the memory and state structure** (skip anything that already exists):
   - `.claude/memory/research/.gitkeep`, `.claude/memory/lessons/.gitkeep`
   - `.claude/memory/decisions.md` — seed with `# Architecture Decisions`
   - `.claude/memory/INDEX.md` — generate it: `plugins/dev-workflow/scripts/memory-index.sh`
   - `.claude/state/progress/`, `.claude/state/sessions/`
   - **Migrate** an existing `.claude/PROGRESS.md`: move it to
     `.claude/state/progress/<current-branch-slug>.md`.
   - Add `.claude/state/` to `.gitignore` — work state is local and per-branch;
     `.claude/memory/` stays committed, lessons included.
```

Dans l'étape 4, remplacer la question par : les leçons et la recherche sont committées, l'état est toujours local — ne demander que si `.claude/memory/` doit être partagé ou ignoré.

- [ ] **Step 5: Rappeler les leçons aux subagents**

Dans `plugins/dev-workflow/skills/orchestrate/SKILL.md`, section « Subagents start blank », ajouter :

```markdown
They also start without the lessons this project has already paid for. `coder` and `reviewer`
read `.claude/memory/lessons/` themselves; for the others, paste any relevant lesson into the
brief — `lesson-guard.sh` protects tool calls, not reasoning.
```

Dans `plugins/dev-workflow/agents/coder.md`, ajouter au début de la procédure :

```markdown
Before writing anything, read `.claude/memory/lessons/*.md`. These are mistakes this project has
already paid for; a level-3 lesson will block the tool call outright, so read them first rather
than discovering them at the wall.
```

Dans `plugins/dev-workflow/agents/reviewer.md`, ajouter aux critères de revue :

```markdown
- **Lessons:** read `.claude/memory/lessons/*.md` and flag any line of the diff that repeats a
  recorded mistake, naming the lesson.
```

- [ ] **Step 6: Version et README**

Dans `plugins/dev-workflow/.claude-plugin/plugin.json`, passer `"version"` à `"0.4.0"` et compléter la description : `"… session handoff, lessons learned that block repeat mistakes, coding rules, clean git workflow, and multi-model orchestration for Claude Code."`

Dans `README.md`, ajouter une section décrivant les trois mémoires, l'état scopé par branche, le registre de sessions, et l'échelle des trois niveaux avec l'échappatoire `DW_OVERRIDE=<slug>`.

- [ ] **Step 7: Vérification finale**

Run: `bash plugins/dev-workflow/tests/run.sh`
Expected: `=== ALL SUITES PASSED ===`

Run: `python3 -c "import json;json.load(open('plugins/dev-workflow/hooks/hooks.json'));json.load(open('plugins/dev-workflow/.claude-plugin/plugin.json'));print('json ok')"`
Expected: `json ok`

Run: `for f in plugins/dev-workflow/scripts/*.sh plugins/dev-workflow/scripts/lib/*.sh; do bash -n "$f" || echo "SYNTAX $f"; done`
Expected: aucune sortie.

- [ ] **Step 8: Commit**

```bash
git add plugins/dev-workflow README.md
git commit -m "feat(dev-workflow): lessons skill, per-branch handoff docs, v0.4.0"
```

---

## Vérification manuelle de bout en bout

À faire une fois les six tâches passées, dans un projet jetable — les tests couvrent les scripts un par un, pas leur intégration réelle dans Claude Code :

1. `/dev-workflow:setup` dans un projet neuf : `.claude/state/` créé et gitignoré, `.claude/memory/lessons/` créé, un `PROGRESS.md` préexistant migré.
2. Deux sessions Claude Code sur **deux branches** : chacune voit sa propre progression, aucune ne voit celle de l'autre, chacune signale l'autre en une ligne.
3. Deux sessions sur la **même branche** : la seconde affiche le bandeau d'avertissement.
4. Tuer une session avec `kill -9`, en démarrer une autre : l'entrée fantôme a disparu du registre.
5. Une leçon de niveau 3 bloque bien la commande ; `DW_OVERRIDE=<slug>` la laisse passer et incrémente `overrides`.
6. Commiter, puis rouvrir une session : le bandeau de péremption apparaît.
