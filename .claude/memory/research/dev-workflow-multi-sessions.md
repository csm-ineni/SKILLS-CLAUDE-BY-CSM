# Multi-Sessions Surface du Plugin dev-workflow

**Question :** Quelle est la surface "multi-sessions / continuité entre sessions" du plugin dev-workflow, et quelles sont ses lacunes concrètes ?

**Date :** 2026-09-11

## Surface actuelle

### Tableau des hooks

| Événement | Script | Logique |
|-----------|--------|---------|
| **SessionStart** | session-context.sh | Injecte standing policy (40+ lignes), puis contenu brut de `.claude/PROGRESS.md` et `.claude/memory/INDEX.md` dans contexte. Pas de validation de correspondance branche. |
| **UserPromptSubmit** | prompt-reminder.sh | Émission throttlée (1x/30min) d'un rappel unique de workflow. Timbre dans `XDG_CACHE_HOME/claude-dev-workflow/reminder-{cksum projet}`. Clé par projet entier, pas par branche. |
| **PreToolUse (Bash)** | guard-commit.sh | Scan regex pour attribution Claude dans commits/PRs/tags. Inspecte aussi fichiers message (-F/--file/--body-file). Exit 2 = blocage; exit 0 = allowed. Pas de détection branche. |
| **PreCompact** | precompact-reminder.sh | Rappelle mise-à-jour PROGRESS.md avant compaction. Efface timbre reminder pour réinjection standing policy post-compaction. Avertissement seulement, pas forcé. |

### Contrat PROGRESS.md

- **Fichier :** `.claude/PROGRESS.md` unique par projet
- **Structure :** Template fixe (Updated, Branch, Current task, Done, Next step, Open questions, Watch out)
- **Écriture :** Overwrite-only via skill session-handoff, "à chaque milestone" pas juste fin de session (session-handoff/SKILL.md:42)
- **Lecture :** SessionStart l'injecte brut en bloc dans contexte (session-context.sh:22-26)
- **Scope :** Aucun scoping par branche, worktree, ou session ID
- **Règles :** "Done"=vérifié, "Next step"=exécutable-à-l'aveugle, max ~60 lignes, liens vers .claude/memory/ au lieu d'inline
- **Pas de :** verrou, timbre, détection péremption vs branche courante

### Contrat .claude/memory/

**INDEX.md :** Liste de `- [topic](research/<file>.md) — one-line answer (YYYY-MM-DD)`. Écrit après recherche significative. Consulté avant chaque recherche.

**research/<kebab>.md :** Template avec Question, Answer (condensé), Sources (URLs + file:line), Date. Entrée contredite = correction/suppression immédiate. Pas de TTL.

**decisions.md :** Architecture choix (decision, why, date), pas recherche codebase.

## Lacunes multi-sessions concrètes

1. **PROGRESS.md unique sans scoping branche** (session-context.sh:8, session-handoff/SKILL.md:12)
   → Deux sessions parallèles sur feature-A et feature-B écrasent le même fichier

2. **Pas de verrou sur PROGRESS.md ni INDEX.md** (aucune synchronisation)
   → Écritures concurrentes = race condition garantie, dernière écriture gagne

3. **SessionStart compare pas Branch: vs git branch courante** (session-context.sh:22-26)
   → Injecte PROGRESS.md brut même si branche changée depuis la dernière session

4. **Pas de "resume" explicite** (standing policy dit "apply WITHOUT being asked" mais aucun signal fort)
   → Agent peut ignorer PROGRESS.md et redémarrer l'exploration zéro

5. **prompt-reminder throttle par projet, pas branche** (prompt-reminder.sh:13)
   → Toutes branches partagent même timbre, pas de distinction worktree

6. **Pas d'expiration/TTL pour .claude/memory/research** (project-memory/SKILL.md:34 dit "correction immédiate si contredite" mais zéro automatisation)
   → Entrées deviennent obsolètes silencieusement (versions changent, APIs bougent)

7. **Standing policy 40+ lignes injectée à chaque SessionStart** (session-context.sh:12-20)
   → Potentiel bruit en longues sessions, pas d'adaptation dynamique au contexte

8. **INDEX.md pas append-only/fusionnable** (project-memory/SKILL.md:28)
   → Deux sessions écrivant research simultanément = clobbering, dernière session gagne

9. **guard-commit.sh ne détecte pas main branch** (guard-commit.sh)
   → "Red flag: About to commit on main" = feedback humain, pas blocage automatique

10. **PROGRESS.md n'a qu'un timestamp "Updated", pas d'historique milestones** (session-handoff/SKILL.md:16)
    → Traçabilité zéro, impossible de savoir combien de sessions ont touché le projet ou quand

11. **Pas d'auto-détection PROGRESS.md "stale" après rebase/merge destructif** (session-context.sh:32-35)
    → Injecte PROGRESS.md même après `git rebase -i` ou destructive checkout, peut être orphelin

12. **setup:32 demande team-shared vs personal .claude/memory/** (ambiguïté)
    → Si team-shared + branches parallèles = clobbering garanti; si personal = chaque session refait recherches

## Conclusion

Le système assume **une seule session active par projet à la fois**. L'absence de scoping branche, verrous, et historique le rend fragile sous :
- worktrees multiples
- sessions parallèles
- rebases destructifs
- longues sessions avec compactions

Priority fixes : (1) scoping PROGRESS.md par branche, (2) verrous INDEX.md, (3) validation Branch: vs git branch courante, (4) TTL memory.
