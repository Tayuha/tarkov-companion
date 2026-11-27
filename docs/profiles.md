# Local profiles

A profile holds the player data for one game mode: the recorded player level,
the quest states and the objective counters. Profiles are local-only. They live
in the `profiles` table of the SQLite database (`docs/schema.md`) and are read
and written only through `ProfileRepository` in `tarkov_companion_data`
(`app/packages/data/lib/src/profiles/profile_repository.dart`).

This document covers creation, activation, editing, reset, deletion and the
Profiles screen. The portable progress file has its own document:
[`docs/progress-format.md`](progress-format.md).

## One profile per game mode

The modes are the bundle modes (`GameMode`):

| Wire value | Enum | Notes |
|---|---|---|
| `regular` | `GameMode.regular` | Auto-created on first launch. |
| `pve` | `GameMode.pve` | Created explicitly by the user. |
| `pvp-season` | `GameMode.pvpSeason` | Created explicitly by the user. |

There is **at most one profile per mode**. This is enforced by the `UNIQUE`
constraint on `profiles.gameMode`, so no repository code can create a second
`regular` profile even if two calls race. A profile id is stable for the life of
the profile and is independent of the mode.

`ProfileRepository.list()` returns every profile oldest first (`createdAt`, then
`id`). `byId(id)` returns one profile or `null`. Neither changes anything.

## First launch

`ensureFirstLaunch()` is the startup entry point and is idempotent:

- **No profiles exist** — it inserts one `regular` profile at player level 1 and
  makes it active. Profile and setting are written in one transaction.
- **Profiles exist** — it returns the active profile (repairing a bad active id,
  see below) and creates nothing. Calling it on every start cannot duplicate or
  reset a profile.

## Explicit creation

`createForMode(GameMode)` creates the profile for an explicit mode and activates
it in the same transaction. It returns a typed result:

| Result | Meaning |
|---|---|
| `ProfileCreated` | A row was inserted and is now active. |
| `ProfileAlreadyExists` | The mode already had a profile. The existing row is returned, nothing is inserted, and the active profile is **not** changed. |

The duplicate case is a result rather than an exception because it is an
ordinary user action. Switching to the existing profile is always an explicit
`activate` call, so creating a mode never silently moves the tracker away from
where the user was working.

Creating a mode starts with an empty progress set. Other profiles and their
quest/objective rows are untouched.

## Activation and the single-active invariant

The active profile is stored as `settings.activeProfileId` in `appSettings`
(see `docs/settings.md`). The key is the table's primary key, so there is
**exactly one active id row** at any time; there is no list of active profiles
to keep consistent.

`activate(id)`:

1. validates that the profile exists;
2. writes the id to the active setting, replacing the previous value;
3. returns the profile.

A missing id throws `ProfileNotFoundError` (carrying the requested id) and
leaves the previous active profile and every other row unchanged. Activating a
profile that is already active is a no-op write of the same value.

`active()` returns the active profile, or `null` when no profile exists at all.

## Repair behavior

`active()` and `ensureFirstLaunch()` never throw for a stored active id that
disagrees with the table. When the setting is missing, unreadable (bad JSON or a
non-string value), or points at an id that no longer exists, the repository:

1. chooses the `regular` profile when it exists; otherwise the **oldest**
   profile by `createdAt`, with `id` as the deterministic tie-breaker;
2. rewrites `settings.activeProfileId` to that profile in the same transaction;
3. reports a message through the repository's `onRepair` callback (wire it to
   the application logger).

The repair is deterministic and idempotent: running it again on the same
database yields the same active profile. Unreadable settings values are treated
exactly like missing ones, matching `SettingsRepository`.

A profile whose `gameMode` is not one of the three known values is treated as
unknown for creation purposes (it cannot be created again) but still
participates in the oldest-profile fallback. Mode values are written by this
repository only, so this is a corruption case, not an expected one.

## Transactions, ids and clock

- **Transactions** — first launch (insert + active setting) and explicit
  creation (insert + active setting) each run inside one database transaction.
  A failure cannot leave an active id pointing at a profile that was not
  inserted.
- **Ids** — the default generator is `profile-` plus 16 cryptographically random
  bytes in lowercase hex (`Random.secure`), so ids are unique without a
  dependency. The repository retries if an injected generator repeats an id and
  raises `StateError` when no unique id can be produced.
- **Clock** — `createdAt` and `updatedAt` come from the injectable clock
  (default `DateTime.now`), so tests can pin timestamps. Activation does not
  change `updatedAt`: switching profiles is not a change to a profile fact.
- **Schema** — profiles already exist in the v5 schema. This task adds no
  migration and no column.

## Editable facts

The shipped profile model records the player level. **Faction is not a profile
fact**: the `profiles` table has no faction column, and the quest availability
engine derives its answer from level, recorded quest states and objective
counts. Adding a faction later is a schema migration, not a UI change.

`updatePlayerLevel(id, level)` accepts `1`–`99`
(`ProfileRepository.minPlayerLevel` / `maxPlayerLevel`) and throws
`ProfileFactValidationError` for anything else before writing. A successful
update changes `playerLevel` and `updatedAt` only.

Availability is **derived on read**, never stored. After a level change the next
`QuestRepository.statuses` / `availableQuests` call sees the new level; no
restart and no cache invalidation is involved. The shell still refreshes the
Quests tab after a profile edit because the mounted list keeps its last query
result; `HomeShell` bumps a revision key when `ProfilesScreen.onProfileChanged`
fires.

## Reset

`resetProgress(id)` clears the profile's `questProgress` and
`objectiveProgress` rows in one transaction. The profile row, its player level,
the active id and every other profile stay. It returns
`ProfileResetResult(questStatesCleared, objectiveCountsCleared)` and refreshes
`updatedAt`. A reset of an already empty profile returns zero counts.

## Delete

`delete(id)` removes the profile and its progress rows in one transaction. It
returns `ProfileDeletionResult(deleted, active)`:

* deleting a **non-active** profile leaves the active id alone;
* deleting the **active** profile activates another one deterministically:
  `regular` when it still exists, otherwise the oldest remaining profile
  (`createdAt`, then `id`);
* deleting the **last** profile removes the active setting entirely and returns
  `active: null`. `active()` then returns `null`; `ensureFirstLaunch()` creates a
  fresh regular profile at level 1 on the next start. The Profiles screen shows
  an empty state with the "add profile" chips instead.

A missing id throws `ProfileNotFoundError` and changes nothing.

## Export and import

The Profiles screen exposes:

* **Export active** and **Export all**, using the platform file dialog;
* **Import file**, which validates and previews before any write.

Merge is the default and never deletes a row; replace requires a second
confirmation. The document, checksum algorithm, error messages and recovery
steps are in [`docs/progress-format.md`](progress-format.md).

## Tests

`app/packages/data/test/profiles/profile_repository_test.dart` covers, in
memory and on a reopened file-backed database:

- first launch creating exactly one regular profile at level 1 and activating
  it, with a second call changing nothing;
- explicit PvE and season creation, including an empty progress set and
  untouched regular progress and level;
- duplicate-mode creation returning the existing profile without switching;
- switching, with exactly one active setting row;
- activating a missing id throwing `ProfileNotFoundError` and preserving the
  previous active profile;
- repair for a missing setting, a dangling id, an unreadable value, and the
  oldest-profile and id tie-break fallbacks;
- ids being unique, injected generators being honored and retried, timestamps
  coming from the injected clock, and the active profile surviving a reopen.

`profile_editing_test.dart` covers the level range, a level change unlocking a
quest on the next read, reset isolation between profiles, deletion of active,
non-active and last profiles, and first launch after deleting everything.
`progress_format_test.dart`, `progress_import_test.dart` and the feature
`profiles_screen_test.dart` cover the portable format, preview, merge, replace,
rollback, file export and every screen action.
