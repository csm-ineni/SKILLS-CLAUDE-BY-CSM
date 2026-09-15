# Surface multi-agents du plugin dev-workflow

**Question:** Quelle est aujourd'hui la surface multi-agents du plugin dev-workflow (agents déployés, couverture, lacunes) ?

**Answer:** Le plugin expose 4 agents (browser-tester/Sonnet, coder/Opus, researcher/Haiku, reviewer/Opus) orchestrés via la skill `orchestrate`. Celle-ci couvre table de délégation, briefs explicites, feedback loops, et parallélisme en lecture. Les lacunes majeures : pas de format retour structuré commun, pas de protection contre conflits d'écriture entre coders, pas d'agent planner/architect, isolation par worktree absente, zéro trace/log des délégations, pas de retry après échec agent, pas de convention labeling, pas d'agent tests unitaires, et état non partagé entre agents.

## Agents déployés

### 1. browser-tester (Sonnet)

**Outils:** Read, Grep, Glob, Bash, Write, Edit

**Taille prompt:** ~300 lignes (browser-tester.md)

**Fonction:** Écrit et exécute des tests Playwright E2E pour les flux UI. Détecte le setup existant, choisit le gestionnaire de paquets, configure les tests, lance les runs headless, puis rapporte un diagnostic condensé (setup, specs écrits, pass/fail counts, diagnoses par failure).

### 2. coder (Opus)

**Outils:** Read, Grep, Glob, Bash, Write, Edit, Skill

**Taille prompt:** ~240 lignes (coder.md)

**Fonction:** Implémente des tâches bien spécifiées (features, refactoring, bugs, tests). Réutilise le code existant, applique la skill `coding-rules`, teste et vérifie les builds avant de déclarer fini. Retourne Done/Verification/Notes.

### 3. researcher (Haiku)

**Outils:** Read, Grep, Glob, Bash, WebFetch, WebSearch, Write

**Taille prompt:** ~240 lignes (researcher.md)

**Fonction:** Explore le codebase ou recherche en documentation/web. Retourne une conclusion condensée (2-6 phrases), des refs de code/URLs, puis met à jour la mémoire du projet sous `.claude/memory/research/`.

### 4. reviewer (Opus)

**Outils:** Read, Grep, Glob, Bash (read-only)

**Taille prompt:** ~240 lignes (reviewer.md)

**Fonction:** Revue adversariale d'un diff. Cherche priorité: correctness, regressions, tests manquants, violations SOLID/DRY, sécurité. Rend un verdict: **ready** / **ready after nits** / **needs work**.

## Couverture de la skill orchestrate

**Table de délégation explicite** (orchestrate.md L10-18):
| Task | Agent | Brief requise |
| Codebase exploration | researcher | question précise, où chercher, shape réponse |
| Library/API/web research | researcher | question, lib + version, shape |
| Implémentation bien-spécifiée | coder | goal, files, constraints, verification |
| Revue de diff | reviewer | base ref exact, intent |
| Tests Playwright | browser-tester | start command/URL, flows, edge cases |

**Briefs structurés** (orchestrate.md L25-40):
- researcher: question précise, chemins/lib, shape attendue
- coder: goal explicite, files, constraints, commands de vérification
- reviewer: diff range (`git diff <base>...HEAD`), intent en 1 phrase
- browser-tester: start command, flows à couvrir, edge cases

**Feedback loop** (orchestrate.md L44-48):
- reviewer returns "needs work" → renvoyer les findings au coder comme nouveau brief
- coder reports "task bigger than specified" → re-scope: split + researcher first si besoin
- Spot-check claims: re-run 1 seul verification command, pas full re-review

**Parallelisme** (orchestrate.md L50-54):
- Read-only subtasks (researchers, reviewers) en parallèle
- JAMAIS 2 coders dont les file sets se chevauchent
- Fan-out modeste (~3-4), au-delà la qualité synthèse chute

**Non-redo rule** (orchestrate.md L57-58): "Don't redo delegated work yourself; wait for the result." + findings via `project-memory` skill.

## Lacunes concrètes

1. **Pas de format de retour structuré commun** (browser-tester.md L26-28, coder.md L20-24, researcher.md L19-24, reviewer.md L24-26) — chaque agent retourne un format libre (researcher: Answer/Evidence/Gaps/Memory; coder: Done/Verification/Notes; browser-tester: setup/specs/pass-fail/diagnoses; reviewer: ranked list + verdict). Aucun schéma JSON commun pour parser/synthétiser les résultats.

2. **Pas de protection système contre conflits d'écriture entre coders** (orchestrate.md L53) — "Never run two coder agents whose file sets may overlap" est une instruction au conductor, pas une barrière système. Si les briefs se chevauchent malgré tout, corruption des fichiers garantie.

3. **Pas d'agent "planner"/"architect"** (agents/, orchestrate.md L10-18) — zéro décomposition automatique des grandes features en sous-tâches; pas d'analyse d'impact, pas de planification itérative/progressive.

4. **Pas d'isolation par git worktree** (agents/**, orchestrate.md) — chaque agent travaille sur la même branche/arborescence. Une modification accidentelle d'un agent peut bloquer ou corrompre le travail d'un autre.

5. **Pas de trace/log centralisé des délégations** (orchestrate.md L1-63) — aucun journal des appels agents (qui a appelé qui, quand, avec quelle brief, quel résultat). Zéro audit trail des orchestrations.

6. **Pas de reprise après échec d'un agent** (orchestrate.md L48, L54) — timeout, crash, ou refus d'un agent → pas de mécanisme de retry ou rollback. Instruction: "wait for the result" sans timeout handler.

7. **Pas de convention de nommage/labeling des exécutions** (agents/) — impossible de filtrer/trier les appels agents par type, domaine, sévérité, priorité. Aucun tagging des résultats pour exploitation downstream.

8. **Absent: agent dédié aux tests unitaires** (agents/) — browser-tester couvre Playwright; jest/vitest/mocha/etc sont du ressort du coder seul dans son brief. Pas de parallélisation possible des tests unitaires.

9. **Pas de doc sur le "Workflow" tool dans plugin.json** (plugin.json L1-10, orchestrate.md) — plugin.json ne liste que name/displayName/version/author, aucune API des agents/skills. orchestrate.md mentionne "Workflow skill" mais le JSON ne l'expose pas.

10. **Pas d'état partagé entre agents** (orchestrate.md L24, L43) — chaque agent démarre vierge, sans accès aux vars/diffs/branches des autres. Si researcher découvre qqchose, le coder ne le voit que si le conductor le répète intégralement dans son brief.

## Sources

- `/Users/ineni/Documents/CHEIKH/CSM/SKILLS-CLAUDE-BY-CSM/plugins/dev-workflow/agents/browser-tester.md` (lines 1-29)
- `/Users/ineni/Documents/CHEIKH/CSM/SKILLS-CLAUDE-BY-CSM/plugins/dev-workflow/agents/coder.md` (lines 1-25)
- `/Users/ineni/Documents/CHEIKH/CSM/SKILLS-CLAUDE-BY-CSM/plugins/dev-workflow/agents/researcher.md` (lines 1-25)
- `/Users/ineni/Documents/CHEIKH/CSM/SKILLS-CLAUDE-BY-CSM/plugins/dev-workflow/agents/reviewer.md` (lines 1-27)
- `/Users/ineni/Documents/CHEIKH/CSM/SKILLS-CLAUDE-BY-CSM/plugins/dev-workflow/skills/orchestrate/SKILL.md` (lines 1-63)
- `/Users/ineni/Documents/CHEIKH/CSM/SKILLS-CLAUDE-BY-CSM/plugins/dev-workflow/.claude-plugin/plugin.json`
- `/Users/ineni/Documents/CHEIKH/CSM/SKILLS-CLAUDE-BY-CSM/README.md` (lines 1-82)

**Date:** 2026-09-11
