# Quest engine

The quest engine turns the catalog's `task` records and the active profile's
own rows into three things the UI needs: a quest detail, a derived availability
state, and recorded objective progress. It lives in the pure-Dart data package:

- `app/packages/data/lib/src/quests/quest_detail.dart` — detail read models;
- `app/packages/data/lib/src/quests/quest_availability.dart` — availability,
  lock reasons and objective progress;
- `app/packages/data/lib/src/quests/quest_repository.dart` — reads and writes.

No derived availability is stored. `questProgress` keeps only the player's
recorded state, and `objectiveProgress` keeps only recorded counts; every
locked/available/in-progress/completed answer is computed when it is read.

## Public API

```dart
final repository = QuestRepository(db);

Future<QuestDetail?> detail(String questId, {String? profileId});
Future<List<QuestObjective>> objectivesFor(String taskId);

Future<List<QuestStatus>> statuses(String profileId);
Future<QuestStatus?> status(String profileId, String questId);
Future<List<QuestStatus>> availableQuests(String profileId, {QuestSort? sort});
Future<List<OrphanedQuestProgress>> orphanedProgress(String profileId);

Future<void> setQuestState(
  String profileId,
  String questId,
  QuestProgressState state,
);
Future<void> setObjectiveCount(
  String profileId,
  String questId,
  String objectiveId,
  int count,
);
```

Every read or write is scoped to one `profileId`. A missing profile throws
`QuestProfileNotFoundError`; it never falls back to another profile. The
catalog query (`QuestRepository.query`) is independent and still reports the
raw recorded state used by its `state` filter.

Reads that accept a profile also scope tasks to that profile's game mode (see
[Game modes](#game-modes)). Without a profile there is no active mode, so the
catalog and detail lookup stay mode-agnostic.

## Quest detail

`QuestDetail` is built from the canonical task payload plus the split-out
`taskObjectives` rows:

- identity: `id`, `name`, normalized name, description, trader/map ids and
  local display names;
- gates: minimum player level, `taskRequirements`, `traderRequirements`;
- objectives: type, description, required count, optional flag, maps,
  item/target references and the complete objective payload;
- `finishRewards`: items, trader standing, skill levels, achievements, trader
  and dialogue unlocks, location unlocks, offer unlocks, craft unlocks and
  customizations;
- unlocks: quests in the **current dataset** whose `taskRequirements` name this
  quest. A quest removed upstream cannot appear as an unlock.

Objectives are ordered by objective id. `objectivesFor` returns an empty list
for an unknown quest; `detail` returns `null`. `detail(id, profileId: …)` also
returns `null` for a quest scoped to another game mode, so a stale link cannot
open a quest the active profile cannot see.

## Game modes

Each bundle task may carry `gameMode`, an optional string list. `statuses`,
`status`, `availableQuests` and the profile-scoped form of `detail` keep only
tasks whose list is empty or contains the profile's `profiles.gameMode`. A
missing, empty or malformed list is treated as mode-agnostic so older bundles
and hand-written fixtures keep working. The catalog query applies the same rule
whenever `QuestQuery.profileId` names a real profile; see
[`quest-queries.md`](quest-queries.md).

A PvE-only task is therefore absent from a regular profile's catalog and
available view even though its row is still in `tasks`. Writing state or an
objective count for it throws `QuestNotFoundError`, exactly like a quest that
was removed upstream. Progress rows for a task that exists in another mode are
not orphans: switching to that mode's profile brings the quest back.

## Available ordering

`availableQuests` returns only `QuestAvailability.available` statuses. Without
`sort` it uses the recommended order: minimum player level ascending (missing
last), trader id ascending (missing last), normalized name ascending, quest id
ascending. `sort` replaces the primary criterion with any `QuestSortField`
(name, level, trader or map); ties remain normalized name then quest id, and
missing values stay last in both directions. The available view exposes level,
trader, map and name.

## State machine

`QuestProgressState` has four values. Three are persisted verbatim in
`questProgress.state`; `notStarted` is the absence of a row.

| Recorded state | Stored value | Availability |
|---|---|---|
| `notStarted` | no row | `locked` or `available`, computed from the gates |
| `inProgress` | `in-progress` | `inProgress` |
| `completed` | `completed` | `completed` |
| `failed` | `failed` | `locked` (`QuestFailed`) unless the payload says `restartable`; a restartable failed quest is evaluated like a fresh start |

`setQuestState(..., notStarted)` deletes the state row. It never deletes
objective counts: reverting a completion keeps what the player recorded.
Changing the state never rewrites another quest: availability is derived, so a
dependent quest is locked or unlocked the next time it is read.

`QuestAvailability` is exactly `locked`, `available`, `inProgress`,
`completed`.

## Availability rules

For a quest that is not recorded as in progress or completed, the engine
starts from `available` and adds a blocking reason for each unmet gate:

1. **Minimum player level** — the profile's `profiles.playerLevel` must be at
   least `tasks.minPlayerLevel`. A null requirement does not block.
2. **Prerequisite quests** — every `taskRequirements` entry must match its
   `status` list exactly:
   - `complete` requires a recorded completion;
   - `active` requires `in-progress`;
   - `failed` requires `failed`;
   - a list is a disjunction (`["active", "complete"]` accepts either).

   A prerequisite missing from the current dataset is reported with
   `prerequisiteInDataset == false` and always blocks. A preserved progress row
   for that missing quest does **not** satisfy it (spec: orphaned progress is
   excluded from dependency math).
3. **Malformed data** — a non-array `taskRequirements`, an entry without a
   task id, an unknown status name, or a non-object task payload adds
   `MalformedPrerequisite` and blocks derived availability.
4. **Cycles** — the engine follows only *unsatisfied* prerequisite edges and
   marks nodes grey/black in an iterative depth-first search. A grey node is a
   cycle; the search always terminates and reports the path in
   `PrerequisiteCycle`. Following only unmet edges means an explicit manual
   completion can break a malformed data cycle instead of locking the rest of
   the chain forever.

If no reason blocks, the quest is `available`. If any blocks, it is `locked`
and every reason is preserved, so the UI can name all unmet gates at once.

### Trader loyalty caveat

`taskRequirements` only cover quests. The bundle also publishes
`traderRequirements` with `requirementType` `level` (loyalty level) or
`reputation`, a comparison and a value. The local schema has **no per-trader
loyalty or reputation value**, and the profile table only stores the player
level. The engine therefore reports these entries as
`TraderRequirementAdvisory`:

- they are included in `QuestStatus.reasons`;
- `TraderRequirementAdvisory.blocksStart` is `false`;
- they never remove a quest from `availableQuests`.

Blocking on a value the app cannot know would hide quests that are actually
available; ignoring the requirement silently would hide useful information.

## Objective semantics

Each objective has a required count:

1. the bundle's `count`;
2. otherwise the objective's `level` (skill / trader level objectives);
3. otherwise `1` (binary objectives such as `visit` or `mark`).

`setObjectiveCount` accepts `0 <= count <= requiredCount`. A negative count or
an over-count throws `QuestProgressValidationError`; an unknown profile, quest
or objective throws its typed error. The check runs inside the write
transaction, so a rejected write leaves the previous count and state unchanged.

Recording the first positive count on a quest with no state row writes
`in-progress` in the same transaction. Recording counts never records a
completion: the state only becomes `completed` through an explicit
`setQuestState`.

`QuestStatus.objectives` contains every objective, optional ones included.
`objectivesSatisfied` ignores optional objectives and is true when every
required objective reaches its count (vacuously true for a quest with no
objectives). `derivedCompletionReady` exposes that answer and
`canMarkComplete` is true when the UI should offer the action.

If the dataset later shrinks an objective's required count below the recorded
count, progress is preserved; the objective simply reads as satisfied. Counts
are never rewritten by a dataset refresh.

## Manual completion override

Marking a quest complete while required objectives are unsatisfied is the
explicit override. It records `completed` and **does not alter any objective
count**. `QuestStatus.manuallyCompleted` is true exactly when the recorded
state is `completed` and `objectivesSatisfied` is false, so the UI can label
the override. A later count change does not silently revert the state.

A quest with no required objectives cannot be overridden: `objectivesSatisfied`
is already true.

## Orphans and data updates

Progress is keyed by stable upstream ids and has no foreign key to game data.
A dataset refresh replaces tasks but never player rows. `orphanedProgress`
lists quest ids that exist in `questProgress`/`objectiveProgress` but not in the
current `tasks` table, grouped with their preserved state, objective counts and
newest update time.

Orphans are never used for prerequisite satisfaction, level gating or the
available-quests view. They are preserved so that a quest that returns in a
later dataset keeps the player's history.

The quest screen lists them in an **Unavailable upstream** panel and keeps the
catalog usable; the detail screen has a dedicated orphan state. A quest that
exists in another game mode is not an orphan: existence is checked against
`tasks`, not against the profile's mode, so switching modes restores it.

## Transactions, ordering and profile isolation

- `setQuestState` and `setObjectiveCount` each run in one database transaction.
- Timestamps come from the injectable repository clock (default
  `DateTime.now`); they are diagnostic and never affect availability.
- `availableQuests` is deterministic: minimum player level ascending (missing
  last), trader id ascending (missing last), normalized name ascending, quest
  id ascending, or the caller's `QuestSort` with the same name/id tie-breakers.
- Switching `profileId` immediately changes every derived state and the mode
  filter; no read ever mixes rows from two profiles or two modes.

## Schema

No schema change was needed. The engine uses the existing `tasks`,
`taskObjectives`, `profiles`, `questProgress` and `objectiveProgress` tables
from schema version 5.
