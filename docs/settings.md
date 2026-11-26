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
  by this repository: `write()` deletes every key outside the four above, so
  obsolete keys from an older version disappear on the next write. `reset()`
  deletes every row.

## Writing and resetting

`write(AppSettings)` validates the freshness range before touching the
database and throws `ArgumentError` for a value outside `1`–`168`; a rejected
write leaves the previous rows untouched. A valid write upserts all four keys
and deletes obsolete keys in **one transaction**. The convenience setters
(`setActiveProfileId`, `setAutoUpdateEnabled`, `setAllowMeteredUpdates`,
`setDataFreshnessHours`) are read-modify-write helpers over `write`.

`reset()` deletes every `appSettings` row and returns `const AppSettings()`.
Reset is scoped to settings only: profiles, quest progress and cached game data
are not affected.

## Tests

`app/packages/data/test/settings/` covers the defaults, JSON encoding, each
setter, persistence across closing and reopening a file-backed database,
rejection of out-of-range writes, fallback for corrupt and out-of-range stored
values, unknown-key handling, removal of obsolete keys, and reset.
