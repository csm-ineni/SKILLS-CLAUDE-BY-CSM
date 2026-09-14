# Design — dev-workflow : sessions parallèles et apprentissage continu

**Date :** 2026-09-14
**Plugin :** `plugins/dev-workflow` (v0.3.0 → v0.4.0)
**Cible :** Claude Code CLI 2.1.268

## Problème

Trois défauts du plugin, constatés fichier par fichier :

1. **L'état de travail est un fichier unique par projet.** `.claude/PROGRESS.md` n'a ni scope de
   branche, ni verrou. Deux sessions ouvertes sur deux features s'écrasent mutuellement.
2. **La reprise est aveugle.** `session-context.sh` injecte `PROGRESS.md` brut sans comparer son
   champ `Branch:` à la branche git réelle, ni sa date au dernier commit. On peut reprendre la
   tâche de `feature-a` en étant sur `feature-b`, ou suivre un plan rendu caduc par dix commits.
3. **Rien ne capitalise sur les erreurs.** La mémoire couvre les faits (`research/`) et les choix
   (`decisions.md`), jamais les échecs. Une leçon comprise mardi est oubliée jeudi, parce que la
   compaction du contexte l'efface et que rien ne la ramène.

`INDEX.md`, édité à la main, perd une entrée dès que deux recherches concurrentes l'écrivent ; le
throttle de `prompt-reminder.sh` est clé par projet entier, jamais par branche.

## Décisions cadrantes

Prises avec l'utilisateur avant rédaction :

| Décision | Choix retenu |
|---|---|
| Échelle visée | Un développeur, plusieurs sessions Claude Code en parallèle sur la même machine |
| Approche | Scoping de l'état par branche **plus** registre des sessions vivantes |
| Politique git | `.claude/state/` gitignoré ; `.claude/memory/` committé, leçons comprises |
| Garde-fou de niveau 3 | Bloquant, avec échappatoire explicite |
| Hors périmètre | Verrou de fichier ; journal de milestones ; lot multi-agents (voir « Reporté ») |

## Faits vérifiés

Vérifiés contre la documentation officielle avant de s'en servir :

- `SessionEnd` existe et est utilisable depuis un plugin (matchers `clear`, `resume`, `logout`,
  `prompt_input_exit`, `other`). Son exécution **n'est pas garantie** si le process est tué —
  budget 1,5 s. Il ne peut donc pas être la seule source de vérité du registre.
- `SessionStart` reçoit sur stdin `session_id`, `cwd`, `source` (`startup`/`resume`/`clear`/
  `compact`/`fork`), `permission_mode`, `hook_event_name`. Son stdout en texte brut est injecté
  dans le contexte — mécanisme déjà utilisé par le plugin.
- `UserPromptSubmit` reçoit `session_id` et `prompt`.
- `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT` et `CLAUDE_PLUGIN_DATA` sont garanties dans un hook
  de plugin.
- Frontmatter d'agent documenté : `name`, `description`, `tools`, `model`, `permissionMode`,
  `skills`, `memory`, `mcpServers`, `maxTurns`, `isolation`, `background`, `effort`, `hooks`,
  `disallowedTools`. **`color` n'est pas documenté** alors que `coder.md` l'utilise.

Parsing du JSON d'entrée : on reprend l'idiome déjà en place dans `guard-commit.sh` — `jq` s'il
est présent, sinon `python3`, sinon `python`, et à défaut un avertissement sur stderr avec
`exit 1` (non bloquant) plutôt qu'un échec silencieux.

## Architecture

### Disposition des fichiers

```
.claude/
  memory/                          COMMITÉ — savoir durable et partageable
    INDEX.md                       généré par memory-index.sh, jamais édité à la main
    research/<slug>.md             faits : librairies, API, codebase
    decisions.md                   choix d'architecture
    lessons/<slug>.md              NOUVEAU — erreurs comprises, déclenchables
    lessons/archive/<slug>.md      leçons mises en sommeil
  state/                           GITIGNORÉ — état de travail, local et éphémère
    progress/<branch-slug>.md      remplace .claude/PROGRESS.md
    sessions/<session-id>.json     registre des sessions vivantes
```

Règle unique : **la mémoire se partage, l'état de travail non.**

### Slug de branche

Source : `git branch --show-current`. `/` → `-`, tout caractère hors `[A-Za-z0-9._-]` → `-`,
séquences de `-` réduites à un seul, troncature à 80 caractères. HEAD détaché →
`detached-<sha7>`. Hors dépôt git → `no-branch`. Le slug est calculé par une fonction unique de
`lib/state.sh`, utilisée par tous les scripts et par la skill `session-handoff`.

### Entrée de registre

`state/sessions/<session-id>.json`, écrite en un seul bloc atomique :

```json
{
  "session_id": "693503f9-…",
  "pid": 41287,
  "branch": "feat/lesson-guard",
  "cwd": "/Users/…/projet",
  "started_at": "2026-09-14T08:42:11Z",
  "last_seen": "2026-09-14T09:05:03Z"
}
```

`pid` vaut `$PPID` capturé au `SessionStart`. **La vivacité du pid fait autorité** : une session
est vivante si `kill -0 <pid>` réussit. Le TTL sur `last_seen` (24 h) n'est qu'un garde-fou
contre la réutilisation de pid après redémarrage — une session peut rester ouverte et inactive
une journée entière sans disparaître du registre. Toute autre entrée est purgée.

### Fichier de leçon

```markdown
---
rule: Ne jamais lancer les migrations Prisma sans --create-only sur la base de dev
why: "2026-03-12 : perte du seed local, 40 min perdues"
tools: Bash
pattern: prisma migrate
level: 2
hits: 3
overrides: 0
last_hit: 2026-09-02
---

<corps : quoi faire à la place, et comment reconnaître la situation>
```

Le frontmatter est **plat** : du YAML imbriqué n'est pas parsable de façon fiable sans
dépendance, et ce fichier est relu à chaque appel d'outil. `tools` liste les outils concernés,
séparés par des virgules (`Bash`, `Edit`, `Write`). `pattern` est une expression régulière
étendue (`grep -E`) confrontée à la commande Bash, ou au chemin visé pour `Edit`/`Write`. Une
leçon sans `tools` ni `pattern` reste au niveau 1 : indexée, jamais injectée.

### Échelle d'escalade

| Niveau | Forme | Déclencheur de promotion |
|---|---|---|
| 1 | Leçon écrite, titre visible dans l'index | Première occurrence de l'erreur |
| 2 | Corps injecté par `lesson-guard.sh` quand le `trigger` matche | Deuxième occurrence |
| 3 | `lesson-guard.sh` bloque (`exit 2`) | Troisième occurrence, ou erreur coûteuse d'emblée |

Une règle qu'il faut répéter est une règle qui a échoué : la promotion en niveau 3 acte qu'on
cesse de faire confiance à la prose. `guard-commit.sh` est déjà, de fait, une leçon de niveau 3
codée en dur ; il reste tel quel et sert de modèle.

**Échappatoire de niveau 3.** Préfixer la commande de `DW_OVERRIDE=<slug-de-la-leçon>` la laisse
passer. Le préfixe est visible dans la chaîne de commande, donc lisible par le hook et traçable.
Chaque contournement incrémente `overrides` dans le fichier de leçon. **Une leçon souvent
contournée est une mauvaise leçon** : `dev-workflow:learn` la rétrograde au niveau 2 ou la
réécrit dès que `overrides` atteint 3. La boucle se corrige elle-même.

## Composants

### `scripts/lib/state.sh` (nouveau)

Bibliothèque sourcée par les autres scripts. Fournit : lecture d'un champ scalaire du JSON stdin
via jq/python ; `dw_branch_slug` ; résolution des chemins (`dw_progress_file`, `dw_sessions_dir`,
`dw_lessons_dir`) ; écriture atomique (`tmp` dans le même répertoire puis `mv`) ; horodatage ISO
8601 UTC ; test de vivacité d'une session. Aucune sortie sur stdout : ces fonctions ne doivent
jamais polluer le contexte injecté.

### `scripts/session-context.sh` (refondu, `SessionStart`)

Dans l'ordre : lire `session_id`/`cwd`/`source` ; purger les entrées mortes du registre (pid éteint, ou last_seen > 24 h) ;
inscrire la session courante ; détecter les collisions ; injecter.

Injection, bornée pour rester lisible :

1. La politique permanente (inchangée, chemins mis à jour).
2. **Bandeau de collision** si une autre session vivante est sur la **même branche** : son âge et
   son cwd, et l'avertissement que la progression est partagée. Sur branche différente : une
   ligne d'information listant les branches occupées.
3. La progression de la branche courante.
4. **Bandeau de péremption** si `git rev-list --count --since="<Updated>" HEAD` est non nul :
   « progression antérieure aux N derniers commits, vérifier avant de reprendre ». Git parse la
   date lui-même, ce qui évite les divergences `date` macOS/GNU.
5. L'index mémoire.
6. Les titres des leçons actives, **plafonnés à 15** (les plus récemment déclenchées d'abord),
   avec le compte total si le plafond est atteint.

Secours : si `.claude/PROGRESS.md` existe encore et que `state/progress/` est absent, l'ancien
fichier est lu et un rappel de migration est affiché.

### `scripts/session-end.sh` (nouveau, `SessionEnd`)

Supprime l'entrée du registre. Rappelle de mettre à jour la progression si elle est plus vieille
que le dernier commit. Optimiste par construction : la purge par pid et TTL du `SessionStart`
reste la garantie réelle.

### `scripts/lesson-guard.sh` (nouveau, `PreToolUse` sur `Bash|Edit|Write`)

Pour chaque leçon active dont `trigger.tools` contient l'outil courant et dont `trigger.pattern`
matche la commande (ou le chemin pour `Edit`/`Write`) :

- niveau 2 → `exit 0` en écrivant le corps de la leçon sur stdout ;
- niveau 3 → `exit 2` avec la règle, le `why`, et la ligne d'échappatoire exacte à utiliser ;
- `DW_OVERRIDE=<slug>` présent dans la commande → laisser passer, incrémenter `overrides`.

Chaque déclenchement incrémente `hits` et met `last_hit` à jour, en écriture atomique. Le script
sort en `0` sans rien dire si aucune leçon ne matche, si le répertoire est absent, ou si une
leçon est malformée — **un fichier de leçon cassé ne doit jamais bloquer le travail**.

### `scripts/memory-index.sh` (nouveau)

Régénère `.claude/memory/INDEX.md` depuis les frontmatters de `research/*.md` et `lessons/*.md`,
en écriture atomique. Supprime la classe entière des pertes d'entrées par écriture concurrente.
Tolérant aux fichiers hérités sans frontmatter : premier titre `#` comme sujet, première ligne
non vide comme résumé.

### `scripts/prompt-reminder.sh` (modifié)

Ajoute le heartbeat (`last_seen` de la session courante) et passe son throttle en clé
projet + branche, pour que deux branches ne se réduisent pas mutuellement au silence.

### `scripts/precompact-reminder.sh` (modifié)

Pointe vers `state/progress/<branch-slug>.md`. Rappelle aussi de promouvoir en leçon ce qui doit
survivre à la compaction — c'est le moment où le contexte est sur le point d'être perdu.

### Skills

- **`session-handoff`** — nouveau chemin ; règle de promotion : un `## Watch out` qui dépasse la
  branche devient une leçon via `dev-workflow:learn`.
- **`project-memory`** — documente les trois mémoires (faits, choix, leçons) et interdit
  l'édition manuelle d'`INDEX.md` au profit de `memory-index.sh`.
- **`learn`** (nouvelle) — quand écrire une leçon, à quel niveau, comment dédupliquer contre les
  leçons existantes, quand promouvoir, quand rétrograder sur `overrides ≥ 3`. Moments de
  capture : l'utilisateur corrige ; le `reviewer` rend *needs work* sur un point déjà vu ; un
  test casse deux fois pour la même raison ; un garde-fou se déclenche.
- **`setup`** — crée `state/` et `lessons/`, ajoute `.claude/state/` au `.gitignore`, migre un
  `.claude/PROGRESS.md` existant vers `state/progress/<branche-courante>.md`.
- **`orchestrate`** — les briefs rappellent que les subagents démarrent vierges et doivent lire
  `lessons/` eux-mêmes.

### Agents

`coder.md` et `reviewer.md` gagnent une instruction : consulter `.claude/memory/lessons/` avant
d'agir, et signaler toute violation d'une leçon existante dans le diff relu.

## Flux de données

**Démarrage :** hook `SessionStart` → purge du registre → inscription → lecture de
`state/progress/<slug>.md` + `memory/INDEX.md` + titres de leçons → stdout injecté.

**Pendant :** chaque prompt rafraîchit `last_seen`. Chaque `Bash`/`Edit`/`Write` traverse
`lesson-guard.sh`, qui injecte ou bloque.

**Capture :** un moment de capture déclenche `dev-workflow:learn` → écriture d'un fichier de
leçon → `memory-index.sh` régénère l'index.

**Fin :** `SessionEnd` retire l'entrée du registre ; `session-handoff` a écrit la progression de
la branche.

## Gestion des erreurs

Principe directeur : **un hook cassé ne doit jamais empêcher de travailler.** Tous les scripts
sortent en `0` en cas d'anomalie, sauf les deux blocages délibérés (`guard-commit.sh` et un
niveau 3 qui matche). Concrètement : répertoire d'état absent → créé à la volée ; JSON stdin
malformé → abandon silencieux ; hors dépôt git → slug `no-branch`, aucune détection de
péremption ; leçon au frontmatter invalide → ignorée ; registre illisible → aucune détection de
collision, le reste de l'injection a lieu.

## Tests

`tests/hooks.test.sh` s'étend, en conservant son style d'entrées en or et son isolation par
`mktemp -d` : slug de branche (cas nominal, `/`, caractères exotiques, HEAD détaché, hors git) ;
purge d'une entrée au pid mort, conservation d'une entrée au pid vivant mais inactive depuis des heures, purge d'une entrée expirée au-delà de 24 h ; collision détectée sur la même branche
et **non** détectée sur une branche différente ; bandeau de péremption présent après un commit
postérieur et absent sinon ; niveau 2 qui injecte sans bloquer ; niveau 3 qui bloque en `2` ;
`DW_OVERRIDE` qui laisse passer et incrémente `overrides` ; leçon malformée qui sort en `0` ;
index régénéré identique quel que soit l'ordre des fichiers ; aucune écriture d'état dans l'arbre
de travail hors `.claude/state/`.

Les tests existants du guard d'attribution et du throttle doivent rester verts.

## Migration

Un projet déjà initialisé continue de fonctionner : les hooks lisent `.claude/PROGRESS.md` en
secours tant que `state/progress/` n'existe pas, en affichant un rappel de migration.
`/dev-workflow:setup` effectue le déplacement et met à jour `.gitignore`. Aucune leçon n'existe
au départ — le répertoire vide est un état nominal, pas une erreur.

Version du plugin portée à **0.4.0** : ajout de fonctionnalités, compatibilité ascendante
préservée par le chemin de secours.

## Reporté

Le lot multi-agents identifié lors de l'audit n'entre pas dans ce spec : format de retour
structuré commun aux subagents, isolation par worktree du `coder`, agents `planner` et
`unit-tester`, journal des délégations. À traiter séparément, après que celui-ci soit en place.
