# Quest tracking states

This page is the canonical state table for the quest tracker. It describes what
is stored, what is derived, and how the UI labels each combination. The
implementation lives in:

- `app/packages/data/lib/src/quests/quest_availability.dart` — states, lock
  reasons and objective progress;
- `app/packages/data/lib/src/quests/quest_repository.dart` — reads and writes;
- `app/packages/features/lib/src/quests/` — badges, catalog, available view and
  detail controls.

See [`quest-engine.md`](quest-engine.md) for the availability algorithm and
[`quest-queries.md`](quest-queries.md) for catalog filtering and sorting.

## State table

Only three values are stored in `questProgress.state`. `notStarted` is the
absence of a row; availability (`locked` / `available`) is always derived from
the profile level and the current dataset.

| Recorded state | Stored `questProgress.state` | Derived availability | Catalog badge | Detail badges | Meaning |
|---|---|---|---|---|---|
| Not started, gates unmet | no row | `locked` | `LOCKED` | state `NOT STARTED`, availability `LOCKED` | A level, prerequisite, failed, cycle or malformed-data reason blocks the start. |
| Not started, gates met | no row | `available` | `AVAILABLE` | state `NOT STARTED`, availability `AVAILABLE` | The profile can accept the quest now. |
| In progress | `in-progress` | `inProgress` | `IN PROGRESS` | state `IN PROGRESS`, availability `IN PROGRESS` | Started. Objective counts are independent of the state. |
| Completed | `completed` | `completed` | `COMPLETED` | state `COMPLETED`, availability `COMPLETED` | Finished, either because every required objective was satisfied or through the explicit override. |
| Failed, not restartable | `failed` | `locked` (+ `QuestFailed`) | `FAILED` | state `FAILED`, availability `LOCKED` | The payload says the quest cannot be restarted, so it does not become available again. |
| Failed, restartable | `failed` | `available` or `locked` by the normal gates | `FAILED` | state `FAILED`, availability reflects the gates | The failed attempt is recorded but the quest can be started again. |

The list keeps `FAILED` even though a non-restartable failure derives as
`locked`; the detail view shows both the recorded state and the derived
availability so the two facts never hide each other.

A profile is required for any derived answer. Without one, the catalog still
renders, every quest reads as `NOT STARTED`, and the detail controls ask for a
profile. Availability is never written back, so changing one quest can unlock
or lock another on the next read with no cache to invalidate.

## Transitions

| Action | Write | Result |
|---|---|---|
| Mark in progress | `setQuestState(..., inProgress)` | Upserts `in-progress`; objective counts are untouched. |
| Mark completed with every required objective satisfied | `setQuestState(..., completed)` | Upserts `completed`; no confirmation is required. |
| Mark completed with unmet required objectives | `setQuestState(..., completed)` after confirmation | The explicit manual override: upserts `completed` and **keeps every objective count unchanged**. `QuestStatus.manuallyCompleted` is true. |
| Mark failed | `setQuestState(..., failed)` | Upserts `failed`; a non-restartable quest then derives as locked. |
| Revert | `setQuestState(..., notStarted)` | Deletes the state row. Objective counts are never deleted. |
| Change an objective count | `setObjectiveCount(...)` | Upserts the count. The first positive count on an unstarted quest also writes `in-progress` in the same transaction. Counts never complete a quest. |

The override rule is intentional: the player may have finished a quest before
recording every counter, so completing it must not fabricate counts. A later
count edit also does not silently revert a recorded completion.

Counts are clamped to `0..requiredCount`. A rejected write throws
`QuestProgressValidationError` before anything is stored, so the previous state
and counts survive.

## Missing quests (orphaned progress)

Progress is keyed by stable upstream ids and has no foreign key to the task
dataset. When a dataset refresh removes a quest:

- `questProgress` and `objectiveProgress` rows are preserved;
- the quest is absent from the catalog, the available view and every
  prerequisite fan-out;
- `QuestRepository.orphanedProgress` groups the preserved rows by quest id with
  their state, objective counts and newest update time;
- the quest screen lists them in the **Unavailable upstream** panel, and the
  detail screen has a dedicated "Quest unavailable upstream" state.

Orphaned progress never satisfies a prerequisite, a level gate or an available
quest. The dependency engine only reads quests in the current dataset, so a
preserved `completed` row for a removed quest cannot unlock anything.

A quest that still exists but belongs to another game mode is **not** an
orphan: switching to a profile of that mode brings it back. For that reason
`orphanedProgress` checks existence in `tasks`, not visibility in the profile's
mode.

## Game-mode scoping

Every task record may carry `gameMode`, an optional list from the bundle.
Scoping follows one rule:

- a missing, empty, non-array or malformed `gameMode` means "all modes", which
  keeps old bundles and fixtures readable;
- otherwise the list is authoritative and must contain the profile's
  `profiles.gameMode` (`regular`, `pve` or `pvp-season`).

The rule is applied to the catalog query, its count, derived statuses, the
available view and quest detail. A PvE-only quest is therefore absent from a
regular profile's catalog even though its row is still in `tasks`, and a write
for it is rejected with `QuestNotFoundError` as if it were not in the active
dataset. Reads without a profile are deliberately unscoped: there is no active
mode to choose.

## Missing data is not a state

A malformed payload or prerequisite list is reported as a lock reason
(`MalformedPrerequisite`) rather than a new state. An unrecognized stored
`questProgress.state` value reads as `notStarted`, so a corrupt import cannot
claim progress the player did not record.

## Verification

| Rule | Test |
|---|---|
| State values round-trip and unknown values read as not started | `app/packages/data/test/quests/quest_query_test.dart` |
| Available / locked / in progress / completed / failed derivation and override | `app/packages/data/test/quests/quest_availability_test.dart`, `quest_progress_test.dart` |
| Orphans listed, preserved and excluded from dependency math | `app/packages/data/test/quests/quest_mode_and_missing_test.dart`, `quest_progress_test.dart` |
| Game-mode scoping in the query and available list | `app/packages/data/test/quests/quest_mode_and_missing_test.dart` |
| Badge mapping, available view, empty state, unavailable panel, mode scoping in the screen | `app/packages/features/test/quests/quest_list_screen_test.dart`, `quest_detail_screen_test.dart` |
