# Quest detail view

`QuestDetailScreen` (`app/packages/features/lib/src/quests/`) is the interactive
page for one quest. It is the presentation half of the quest tracker: the data
package already derives availability, lock reasons and objective progress
(`docs/quest-engine.md`), and this screen renders them and forwards the user's
writes through `QuestRepository`. It is not wired into the app shell; the shell
passes the active profile id.

The screen reads only the local database and makes no network request. The wiki
link is selectable text, not an external browser launch.

## Composition

| Section | Content |
| --- | --- |
| Header | Name, recorded-state badge, computed availability badge, trader, map, minimum level, experience, Kappa/Restartable flags and the wiki link. |
| Objectives | Every objective in an `AppPanel` card, its type, description, optional marker, maps/targets/items, required count, recorded count and an `AppProgressBar`. |
| Requirements | Minimum player level, prerequisite quests with their actual state, trader loyalty/reputation advisories and every structured lock reason. |
| Rewards | Reward item stacks, trader standing, skill levels, trader offers, hideout crafts, customizations and trader/location/achievement unlocks, as `AppStatTile` tiles. |
| Turn-in and required items | Item references projected from objectives (`itemIds`, `questItemId`, `requiredKeyItemIds`). |
| Unlocks | Quests in the current dataset that require this one, with their recorded state. |
| Notes | The description, when upstream publishes one. |
| Status | State controls and write errors. |

Everything is rendered with `AppPanel`, `AppSectionLabel`, `AppButton`,
`AppStatTile` and `AppProgressBar`; the screen writes no colour literal.

Missing fields render nothing: a quest without a description has no Notes
panel, an empty reward block has no Rewards panel, and a quest with no unlocks
has no Unlocks panel. The derived requirement/objective summaries are not
placeholders for missing fields.

## Layout

The content is capped at 1180 logical pixels. From 1080 px it splits into two
columns:

- left: objectives, turn-in/required items, notes;
- right: rewards, requirements, unlocks, status.

Below 1080 the same content is one ordered column. The 1920 concept's quest
chain graph and location panel are not implemented: they are concept-only and
the data has no chain projection or map artwork.

The header uses two different badges on purpose:

- `quest-detail-state` is the **recorded** state (`Not started`, `In progress`,
  `Completed`, `Failed`), which is what the player wrote.
- `quest-detail-availability` is the **derived** state (`Locked`, `Available`,
  `In progress`, `Completed`). A failed quest is recorded as failed and derived
  as locked when it is not restartable.

## Data API used

`QuestRepository.detail(id, profileId: …)` supplies the quest, objectives,
prerequisites, rewards and unlocks, scoped to the profile's game mode: a
PvE-only quest opened under a regular profile reads as not found instead of
showing content the profile cannot use. `QuestRepository.statuses(profileId)`
supplies every derived status once per load, so the screen can show
prerequisites and unlocks without one full derivation per row.

Two small label lookups were added to `QuestRepository`:

- `traderName(id)` reads the `traders` table and falls back to the id;
- `mapName(id)` reads the `maps` table and falls back to the id.

Both return `null` only for a null or blank id. The quest dataset stores
upstream identifiers, so the fallback keeps a partial dataset readable instead
of hiding the reference.

`QuestDetail` exposes convenience projections without changing the bundle
contract: `objectiveItemIds`, `turnInItemIds` (the `giveItem`/`giveQuestItem`
objectives), `rewardItemIds` and `unlockItemIds` (offer and craft items).

## Status rules

| Action | Data call | Effect |
| --- | --- | --- |
| Mark in progress | `setQuestState(..., inProgress)` | Recorded state becomes `in-progress`; the availability badge follows it. |
| Mark completed | `setQuestState(..., completed)` | Recorded state becomes `completed`; if required objectives are satisfied there is no dialog. |
| Mark completed with unmet objectives | `setQuestState(..., completed)` after confirmation | The explicit manual override: the state is completed and every objective count is left untouched. |
| Mark failed | `setQuestState(..., failed)` | Recorded state becomes `failed`; a non-restartable quest derives as locked with a `QuestFailed` reason. |
| Revert | `setQuestState(..., notStarted)` or `inProgress` | Clears the state row. If any objective count is above zero the screen records `inProgress` instead, so recorded counts stay consistent with the recorded state. |

After every write the screen re-reads `statuses` for the active profile, so the
badge, availability, objective hints and dependent-quest availability change
immediately. Progress is always scoped to the passed `profileId`; switching
profiles changes every badge and count, and no row is ever read across
profiles.

With no `profileId` the header, objectives, requirements and rewards still
render, but no progress is read and the status controls are replaced by a hint
to choose a profile.

## Objective controls

Each objective row has a decrement button, a numeric text field and an
increment button. The count is clamped to `0..requiredCount` and persisted
through `setObjectiveCount`. The first positive count on an unstarted quest
also records `in-progress` in the same data transaction. Counts never complete a
quest on their own; completion remains an explicit status action.

The section subtitle and hint change with the derived flags:

- `objectivesSatisfied` is true only when every **required** objective reaches
  its count; optional objectives are tracked but never gate completion.
- With unmet required objectives the screen says completion needs a manual
  override and that counts stay unchanged.
- With every required objective satisfied it says completion can be recorded
  without an override.

## Locked-reason presentation

The `Requirements` section renders the structured reasons from
`QuestStatus.reasons`, not a generic "locked" label:

- player level too low, naming the required and recorded level;
- incomplete prerequisite, naming the quest and the actual state;
- prerequisite missing from the current dataset;
- malformed prerequisite data;
- prerequisite cycle, with the traversal path;
- non-restartable failed quest;
- trader loyalty/reputation advisory, labelled as advisory because the local
  schema stores no loyalty value.

Blocking reasons use a lock icon; the non-blocking trader advisory uses an
information icon. A quest with only advisories still shows `Available`. This is
the UI half of the "explain exactly why a quest is locked" requirement.

## Manual override confirmation

Pressing **Mark completed** while a required objective is unsatisfied opens a
dialog titled *Complete without all objectives?*. Its body states explicitly:
"Objective counts are not changed: the counts you recorded stay exactly as they
are." Confirming records `completed`; cancelling leaves the previous state
untouched.

The data layer then reports `QuestStatus.manuallyCompleted`, and the header
shows a `Manual override` chip. A completed quest with the override continues to
show the untouched counts until the player edits them.

## Item and quest links

- Every reward, turn-in/required, offer and craft item is a link. Tapping one
  pushes `ItemDetailScreen` with the same `CatalogRepository`; the wiki/page
  URL launcher is still out of scope there.
- Every unlocked quest and every prerequisite present in the current dataset
  pushes another `QuestDetailScreen` with the same profile. A prerequisite
  missing from the dataset is listed with its reason but is not tappable.
- No routing state or app-level navigation is added to this screen: it pushes
  with `Navigator` and the shell can still decide how a row opens it.

## States

| State | Rendering |
| --- | --- |
| Loading | Centered spinner (`quest-detail-loading`). |
| Error | Message, detail and retry (`quest-detail-error`, `quest-detail-retry`). |
| Not found | `Quest not found` with the id and a back action (`quest-detail-not-found`). |
| Orphaned progress | The quest is absent from the dataset but the profile has preserved rows. Shows the state, objective counts and update time, and explains that the rows are not used for dependencies (`quest-detail-orphaned`). |
| Loaded | All sections above. |

The back action uses `onBack` when provided; otherwise the screen pops its route,
which is the normal behavior for a pushed detail page.

## Tests

`app/packages/features/test/quests/quest_detail_screen_test.dart` runs against
an in-memory `AppDatabase` seeded with two profiles, the quest graph, trader and
map rows, catalog items and recorded progress. It covers:

- header, objective, requirement and locked-reason rendering;
- the omission rule for descriptions, rewards, items and unlocks;
- the two-column and single-column layouts and the 1180 px content cap;
- level, cycle, malformed-data and trader-advisory reasons;
- every status action persisting and updating both badges, including revert and
  a non-restartable failure;
- objective increment, decrement and text entry with the derived hint and
  progress rail changing;
- manual override confirmation, cancel and unchanged counts;
- reward/turn-in item links pushing the item detail;
- prerequisite and unlock links pushing another quest detail;
- not-found versus orphaned states;
- two-profile isolation of states and objective counts;
- the no-profile read-only mode with no status controls;
- trader/map label fallback to the upstream id; and
- detail goldens at 1440 (two columns) and 900 (one column).
