# App settings

Typed application preferences live in the `appSettings` table of the local
SQLite database and are read and written only through
`SettingsRepository` in `tarkov_companion_data`
(`app/packages/data/lib/src/settings/`).

**Settings are local-only.** They never leave the device, are never uploaded,
and are not part of an export unless a later task explicitly adds them. They
hold no player progress and no secrets; progress lives in the player-data
tables documented in [`schema.md`](schema.md).

## Keys

Every key uses the `settings.` prefix. Each value is a **JSON-encoded string**
in the `value` column, so the stored type is explicit: `"profile-id"`, `true`,
`false`, `24`, `null`.

| Key | Default | Range | Meaning |
|---|---|---|---|
| `settings.activeProfileId` | `null` | any string id or `null` | Profile the tracker reads and writes. `null` means no profile is active; profile existence is validated elsewhere. |
| `settings.autoUpdateEnabled` | `true` | `true` / `false` | Whether background update checks may run. When `false`, no automatic data or app-update request is made until the user checks manually. |
| `settings.allowMeteredUpdates` | `false` | `true` / `false` | Whether automatic downloads may proceed when the OS reports a metered connection. |
| `settings.dataFreshnessHours` | `24` | integer `1`–`168` | Age in hours after which prices are labelled stale and the dataset is considered old. |
| `settings.windowGeometry` | `null` | JSON object or `null` | Desktop window rectangle (`x`, `y`, `width`, `height`) restored on launch. See [`window.md`](window.md). |
| `settings.updateSchedule` | `"daily"` | `"off"`, `"daily"`, `"weekly"` | How often automatic update checks may run. `off` is also written with `autoUpdateEnabled = false`. See [`client-sync.md`](client-sync.md#update-controls). |
| `settings.lastUpdateCheckAt` | `null` | ISO-8601 UTC string or `null` | When the last check completed successfully. The scheduler uses this as its interval anchor. |
| `settings.lastUpdateAttemptAt` | `null` | ISO-8601 UTC string or `null` | When the last check was attempted, including failed and skipped attempts. This is the time shown in the footer. |
| `settings.lastUpdateOutcome` | `null` | `"succeeded"`, `"failed"`, `"skipped-offline"`, `"skipped"` or `null` | Result of the last attempt, shown non-modally in the shell footer. |
| `settings.lastUpdateError` | `null` | string or `null` | Short, user-safe message for the last failed attempt; cleared by the next success. |

The defaults are also the values of `const AppSettings()`; a database with no
rows behaves exactly like a fresh install.

## Missing, invalid and unknown data

- **Missing key** — the field reads as its default. No warning.
- **Corrupt value** — invalid JSON, the wrong JSON type, or a freshness value
  outside `1`–`168` reads as that field's default. `read()` never throws for
  bad stored data; it reports a warning through the repository's `onWarning`
  callback (wire it to the application logger) and keeps the app usable.
- **Unknown key** — ignored by `read()`, and deliberately left in the table so
  a downgrade does not destroy a newer version's data. The table is still owned
  by this repository: `write()` deletes every key outside the set above, so
  obsolete keys from an older version disappear on the next write. `reset()`
  deletes every row.

## Writing and resetting

`write(AppSettings)` validates the freshness range before touching the
database and throws `ArgumentError` for a value outside `1`–`168`; a rejected
write leaves the previous rows untouched. A valid write upserts every key and
deletes obsolete keys in **one transaction**. The convenience setters
(`setActiveProfileId`, `setAutoUpdateEnabled`, `setAllowMeteredUpdates`,
`setDataFreshnessHours`, `setUpdateSchedule`, `recordUpdateOutcome`) are
read-modify-write helpers over `write`.

`setUpdateSchedule` writes the schedule and the legacy `autoUpdateEnabled`
switch together, so the scheduler and the footer never disagree about whether
automatic checks are on. `recordUpdateOutcome` moves the attempt time for every
outcome and the success time only for `succeeded`.

`reset()` deletes every `appSettings` row and returns `const AppSettings()`.
Reset is scoped to settings only: profiles, quest progress and cached game data
are not affected.

## Tests

`app/packages/data/test/settings/` covers the defaults, JSON encoding, each
setter, persistence across closing and reopening a file-backed database,
rejection of out-of-range writes, fallback for corrupt and out-of-range stored
values, unknown-key handling, removal of obsolete keys, and reset.
