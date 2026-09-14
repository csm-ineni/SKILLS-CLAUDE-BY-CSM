# SKILLS-CLAUDE-BY-CSM

Marketplace de plugins Claude Code par CSM. Premier plugin : **dev-workflow**.

## Plugin `dev-workflow`

Améliore l'expérience de développement avec Claude Code :

| Problème | Solution |
|---|---|
| Recherches dupliquées entre sessions | Skill `project-memory` — cache de recherches dans `.claude/memory/` (consulté avant, alimenté après chaque recherche) |
| Perte de progression entre sessions | Skill `session-handoff` + hook SessionStart qui réinjecte le fichier de progression de la branche courante + hook PreCompact avant compaction |
| Deux sessions qui s'écrasent | Progression **scopée par branche** (`.claude/state/progress/<branch-slug>.md`) + registre des sessions vivantes qui prévient quand une autre session travaille sur la même branche |
| Mêmes erreurs répétées | Skill `learn` + hook PreToolUse `lesson-guard.sh` — une leçon de niveau 2 est réinjectée quand l'action correspond, une leçon de niveau 3 **bloque** l'action |
| Règles de code non respectées | Skill `coding-rules` (SOLID, DRY, KISS, YAGNI en critères concrets), chargé automatiquement dès que du code s'écrit |
| Mentions Claude/co-author dans les commits | Triple garde : setting `attribution` vide + instruction dans `feature-workflow` + hook PreToolUse qui **bloque** toute commande `git commit`/`gh pr` contenant une attribution |
| Workflow git non structuré | Skill `feature-workflow` — branche dédiée `feat/...`, Conventional Commits, draft PR dès le premier commit, ready seulement après revue |
| Contexte saturé / coûts | Skill `orchestrate` + agents : `researcher` (Haiku, recherche/exploration), `coder` (Opus, implémentation), `reviewer` (Opus, revue), `browser-tester` (Sonnet, tests navigateur) — le modèle principal (Fable/Opus) orchestre |
| Flux UI non testés | Agent `browser-tester` (Sonnet) — écrit et exécute des tests **Playwright** ; obligatoires avant de passer en ready toute PR qui touche l'UI |

## Installation

Sur n'importe quelle machine, depuis GitHub :

```bash
claude plugin marketplace add csm-ineni/SKILLS-CLAUDE-BY-CSM
claude plugin install dev-workflow@csm-skills --scope user
```

(En local, pour développer le plugin : `claude plugin marketplace add /chemin/vers/SKILLS-CLAUDE-BY-CSM` — les modifications du repo sont alors prises en compte à chaque nouvelle session, sans réinstallation.)

## Mise à jour (dans un projet qui utilise le plugin)

```bash
claude plugin marketplace update csm-skills   # récupère la dernière version du repo GitHub
claude plugin update dev-workflow@csm-skills  # met à jour le plugin installé
```

Puis **redémarre la session Claude Code** (les hooks/skills sont chargés au démarrage). Si le marketplace a été ajouté depuis un chemin local, seule la nouvelle session est nécessaire — pas de commande de mise à jour.

Test rapide sans installer :

```bash
claude --plugin-dir ./plugins/dev-workflow
```

## Démarrage dans un projet

Dans chaque projet où tu veux le workflow :

```
/dev-workflow:setup
```

Crée `.claude/memory/` (research, decisions, lessons) et `.claude/state/` (progression par branche, registre des sessions), migre un éventuel `.claude/PROGRESS.md`, gitignore `.claude/state/`, applique le setting `attribution` global, vérifie `gh auth`.

## Les trois mémoires

| Chemin | Contenu | Écrit par | Versionné |
|---|---|---|---|
| `.claude/memory/research/` | Faits : comportement d'une lib, forme d'une API, comment ce dépôt fait X | skill `project-memory` | oui |
| `.claude/memory/decisions.md` | Choix d'architecture et leur raison | skill `project-memory` | oui |
| `.claude/memory/lessons/` | Erreurs déjà payées, avec un déclencheur qui avertit ou bloque | skill `learn` | oui |
| `.claude/state/progress/<branch-slug>.md` | Où en est le travail **sur cette branche** | skill `session-handoff` | non (gitignoré) |
| `.claude/state/sessions/<session-id>.json` | Sessions Claude Code vivantes (pid, branche, cwd) | hooks | non (gitignoré) |

`.claude/memory/INDEX.md` est **généré** par `plugins/dev-workflow/scripts/memory-index.sh` à partir du frontmatter des entrées — ne jamais l'éditer à la main (deux sessions concurrentes s'y écrasent).

## État par branche et registre des sessions

Le fichier de progression porte le slug de la branche courante (`/` et caractères exotiques remplacés par `-`) : deux fonctionnalités en parallèle ne se marchent plus dessus. Au démarrage, le hook SessionStart :

- purge les sessions mortes (le pid ne répond plus), enregistre la session courante ;
- **avertit** si une autre session vivante travaille sur la même branche (elle avertit, elle ne verrouille pas), et signale en une ligne les sessions sur d'autres branches ;
- injecte la progression de la branche, l'index mémoire et les titres des leçons actives ;
- signale la **péremption** : des commits ont atterri sur la branche après la date `**Updated:**` du fichier de progression.

`UserPromptSubmit` rafraîchit l'entrée de la session (heartbeat), `SessionEnd` la supprime.

## Leçons : trois niveaux

Une leçon est un fichier `.claude/memory/lessons/<slug>.md` au frontmatter plat (`rule`, `why`, `tools`, `pattern`, `level`, `hits`, `overrides`, `last_hit`).

| Niveau | Effet | Quand |
|---|---|---|
| 1 | Titre listé au démarrage de session | Première rédaction, ou pas de `pattern`/`tools` fiable |
| 2 | Leçon complète réinjectée quand le `pattern` correspond à la commande Bash ou au chemin édité | Deuxième occurrence |
| 3 | Action **bloquée** (`exit 2`), échappatoire affichée | Troisième occurrence, ou erreur coûteuse dès le départ |

Échappatoire pour le niveau 3 : préfixer la commande de `DW_OVERRIDE=<slug>`. Chaque contournement incrémente `overrides` — au-delà de 3, la leçon est mauvaise : rétrécir le `pattern`, la scinder, ou la rétrograder en niveau 2. Une leçon non déclenchée depuis six mois part dans `.claude/memory/lessons/archive/` (plus listée, plus matchée).

## Utilisation quotidienne

- **Reprise de session** : automatique — le hook SessionStart injecte la progression de la branche, l'index mémoire et les leçons actives.
- **Fin de session / jalon** : dis « handoff » ou laisse Claude déclencher `session-handoff`.
- **Nouvelle fonctionnalité** : demande la fonctionnalité ; `feature-workflow` impose branche + draft PR.
- **Grosse exploration/recherche** : `orchestrate` délègue à `researcher` (Haiku) pour préserver le contexte.
- **Changement UI / flux utilisateur** : l'agent `browser-tester` (Sonnet) écrit et lance les tests Playwright, en plus des tests unitaires.
- **Avant de passer une PR en ready** : l'agent `reviewer` fait une revue adversariale, leçons comprises.
- **Même erreur deux fois** : dis « on l'a déjà eue » ou laisse Claude déclencher `learn` — la leçon est écrite, puis appliquée par le hook.

## Structure

```
plugins/dev-workflow/
├── .claude-plugin/plugin.json
├── skills/          # setup, project-memory, session-handoff, learn, coding-rules, feature-workflow, orchestrate
├── agents/          # researcher (haiku), coder (opus), reviewer (opus), browser-tester (sonnet)
├── hooks/hooks.json # SessionStart, SessionEnd, UserPromptSubmit, PreToolUse (garde commit + garde leçons), PreCompact
├── scripts/         # lib/state.sh, session-context.sh, session-end.sh, prompt-reminder.sh,
│                    # precompact-reminder.sh, guard-commit.sh, lesson-guard.sh, memory-index.sh
└── tests/           # run.sh — golden-input tests de state, session, hooks, lessons, memory
```

## Désinstallation

```bash
claude plugin uninstall dev-workflow@csm-skills
claude plugin marketplace remove csm-skills
```
