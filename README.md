# SKILLS-CLAUDE-BY-CSM

Marketplace de plugins Claude Code par CSM. Premier plugin : **dev-workflow**.

## Plugin `dev-workflow`

Améliore l'expérience de développement avec Claude Code :

| Problème | Solution |
|---|---|
| Recherches dupliquées entre sessions | Skill `project-memory` — cache de recherches dans `.claude/memory/` (consulté avant, alimenté après chaque recherche) |
| Perte de progression entre sessions | Skill `session-handoff` + hook SessionStart qui réinjecte `.claude/PROGRESS.md` au démarrage + hook PreCompact avant compaction |
| Règles de code non respectées | Skill `coding-rules` (SOLID, DRY, KISS, YAGNI en critères concrets), chargé automatiquement dès que du code s'écrit |
| Mentions Claude/co-author dans les commits | Triple garde : setting `attribution` vide + instruction dans `feature-workflow` + hook PreToolUse qui **bloque** toute commande `git commit`/`gh pr` contenant une attribution |
| Workflow git non structuré | Skill `feature-workflow` — branche dédiée `feat/...`, Conventional Commits, draft PR dès le premier commit, ready seulement après revue |
| Contexte saturé / coûts | Skill `orchestrate` + agents : `researcher` (Haiku, recherche/exploration), `coder` (Opus, implémentation), `reviewer` (Opus, revue) — le modèle principal (Fable/Opus) orchestre |

## Installation

```bash
claude plugin marketplace add /Users/ineni/Documents/CHEIKH/CSM/SKILLS-CLAUDE-BY-CSM
claude plugin install dev-workflow@csm-skills --scope user
```

(Ou depuis un clone git : `claude plugin marketplace add <url-du-repo>`.)

Test rapide sans installer :

```bash
claude --plugin-dir ./plugins/dev-workflow
```

## Démarrage dans un projet

Dans chaque projet où tu veux le workflow :

```
/dev-workflow:setup
```

Crée `.claude/memory/` + `.claude/PROGRESS.md`, applique le setting `attribution` global, vérifie `gh auth`.

## Utilisation quotidienne

- **Reprise de session** : automatique — le hook SessionStart injecte PROGRESS.md et l'index mémoire.
- **Fin de session / jalon** : dis « handoff » ou laisse Claude déclencher `session-handoff`.
- **Nouvelle fonctionnalité** : demande la fonctionnalité ; `feature-workflow` impose branche + draft PR.
- **Grosse exploration/recherche** : `orchestrate` délègue à `researcher` (Haiku) pour préserver le contexte.
- **Avant de passer une PR en ready** : l'agent `reviewer` fait une revue adversariale.

## Structure

```
plugins/dev-workflow/
├── .claude-plugin/plugin.json
├── skills/          # setup, project-memory, session-handoff, coding-rules, feature-workflow, orchestrate
├── agents/          # researcher (haiku), coder (opus), reviewer (opus)
├── hooks/hooks.json # SessionStart, PreToolUse (garde commit), PreCompact
└── scripts/         # session-context.sh, guard-commit.sh, precompact-reminder.sh
```

## Désinstallation

```bash
claude plugin uninstall dev-workflow@csm-skills
claude plugin marketplace remove csm-skills
```
