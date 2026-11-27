# Progress file format

A progress export is one UTF-8 JSON file that carries a player's profile facts
and recorded quest progress. It is designed for backup, for moving progress
between devices, and for hand editing with a text editor. The writer lives in
`app/packages/data/lib/src/profiles/progress_format.dart`; the reader and
writer are pure Dart and have no platform-specific encoding.

The file never contains a device id, an absolute path, a hostname, an account
name or a profile id. A profile is identified by its game mode, so the same
document can be imported on Windows, Linux or Android.

## Version 1

```json
{
  "format": "tarkov-companion-progress",
  "formatVersion": 1,
  "appVersion": "0.1.0",
  "exportedAt": "2026-11-27T09:30:00.000Z",
  "profiles": [
    {
      "gameMode": "pve",
      "playerLevel": 22,
      "quests": [
        {
          "questId": "quest-checking",
          "state": "in-progress"
        },
        {
          "questId": "quest-debut",
          "state": "completed"
        }
      ],
      "objectives": [
        {
          "questId": "quest-checking",
          "objectiveId": "objective-checking-1",
          "count": 3
        }
      ]
    }
  ],
  "checksum": "sha256:aaebd140bab03eb338d35ca4749a4c76db0cd224c00f14406899fd53ca7df3d1"
}
```

The checked-in copy of this document is
`app/packages/data/test/fixtures/profiles/hand-edited-valid.json`, and the
import tests open it directly.

### Fields

| Field | Type | Rules |
|---|---|---|
| `format` | string | Exactly `tarkov-companion-progress`. |
| `formatVersion` | integer | `1` for this document. A newer value is refused. |
| `appVersion` | string | Non-empty; the app that wrote the file. Informational. |
| `exportedAt` | string | ISO-8601 timestamp, written in UTC. Informational. |
| `profiles` | array | 1 to 3 entries, at most one per game mode. |
| `profiles[].gameMode` | string | `regular`, `pve` or `pvp-season`. |
| `profiles[].playerLevel` | integer | `1`–`99`. |
| `profiles[].quests` | array | May be empty. |
| `quests[].questId` | string | Non-empty; unique within the profile. |
| `quests[].state` | string | `in-progress`, `completed` or `failed`. |
| `profiles[].objectives` | array | May be empty. |
| `objectives[].questId` | string | Non-empty. |
| `objectives[].objectiveId` | string | Non-empty; unique for the quest within the profile. |
| `objectives[].count` | integer | `0`–`1000000`. |
| `checksum` | string | `sha256:` plus 64 lowercase hex characters. |

There is no `not-started` state: a quest with no entry is not started. There is
no faction field because the shipped profile model has no faction column; quest
availability depends on level, recorded quest states and objective counts.

Order inside `quests` and `objectives` is not significant. The writer sorts by
id so repeated exports of the same data are byte-identical; a hand-edited file
may use any order.

## Checksum

The checksum covers the document **without** its `checksum` key:

1. decode the JSON object;
2. remove `checksum`;
3. encode it as canonical JSON — object keys sorted recursively, arrays in
   order, no insignificant whitespace (`canonicalJsonEncode` in
   `tarkov_companion_data`);
4. hash the UTF-8 bytes with SHA-256;
5. write `sha256:` followed by the lowercase hex digest.

Because step 3 sorts keys, `{"b":1,"a":2}` and `{"a":2,"b":1}` produce the same
checksum. The `progress_format_test.dart` golden test rewrites every object with
reversed key order and asserts that the checksum and parsed document do not
change.

The writer checksums the canonical form of the whole document, including
`appVersion` and `exportedAt`. Editing any of them requires recomputing the
checksum.

## Export behavior

`ProgressExportWriter.build(appVersion: ..., allProfiles: false)` exports the
active profile; `allProfiles: true` exports every profile in one document,
ordered by `gameMode` wire value. A profile with no progress exports an empty
`quests` and `objectives` array. `ProgressExport.writeTo(path)` writes the
pretty-printed canonical JSON with a trailing newline.

The app's Profiles screen asks for a destination through
`ProgressFilePicker`. The production implementation is
`PlatformProgressFilePicker` (`file_selector`); tests use
`DirectoryProgressFilePicker` with a temporary directory and re-read the file
with `ProgressExportDocument.parse`, asserting the same checksum.

`PlatformProgressFilePicker` is the only unverified seam in this flow: widget
tests cannot open a native GTK/Win32 dialog, so they exercise the same code path
with the directory picker. The file contents, checksum, save location handling
and re-read are covered by the data and feature tests; only the dialog itself is
manual.

## Recovery export

When the database cannot be opened, it is kept and reopened read-only. The
recovery screen offers **Export progress**, which uses
`RecoveryProgressExporter` in
`app/packages/data/lib/src/profiles/recovery_export.dart`.

* **Same file format.** The writer builds the same `ProgressExportDocument`,
  canonical JSON and `sha256:` checksum as `ProgressExportWriter`, so a recovery
  file imports through the normal Profiles flow.
* **One read-only handle.** Every row is read with `RecoveryDatabase.select` on
  the handle the migration runner already opened. The exporter never opens the
  database again and never writes to SQLite; `RecoveryDatabase.execute` is only
  used by tests to prove that a write fails with `attempt to write a readonly
  database`.
* **Destination.** `RecoveryProgressExporter.writeTo` writes
  `progress-recovery-<UTC timestamp>.json` into the app's `<data>/recovery`
  directory, for example
  `progress-recovery-20261127T120000.123456Z.json`. A name collision gets a
  `-1`, `-2`, ... suffix instead of overwriting an earlier export; the screen
  shows the exact written path.
* **Deterministic order.** Profiles sort by game mode wire value, then id;
  quests sort by quest id; objectives sort by quest id, then objective id. A
  second export of the same rows with the same clock is byte-identical.
* **Damaged rows.** A row the format cannot represent is skipped and counted in
  `RecoveryExportDiagnostics.skippedRows`: an unknown quest state, a blank id,
  an unknown game mode, a duplicate profile/quest/objective or a row that
  points at a profile that was not readable. A player level outside `1`–`99` or
  an objective count outside `0`–`1000000` is clamped and counted in
  `normalizedRows`. The screen reports both counts; it does not throw and it
  still writes a valid document.
* **Unreadable tables.** A failed `profiles` read raises
  `NoRecoveryProfilesError` because the format requires at least one profile;
  the screen shows that sentence inline. A failed `questProgress` or
  `objectiveProgress` read is recorded as a warning and the profile is exported
  with an empty list for that table.
* **Diagnostics.** **Export diagnostics** copies the current pre-migration
  backup (when present) and the current `app*.log` files into the same
  `recovery/` directory with `exportRecoveryDiagnostics`. It copies files only:
  it does not read the database and does not open a socket. When there is
  nothing to copy the screen says
  `No backup or log files were available to copy.`

## Import validation

The file is validated as a whole before any write:

1. JSON parses and the top level is an object;
2. `format` is the expected marker;
3. `formatVersion` is supported (newer files are refused with an
   "update the app" message);
4. the checksum matches;
5. every field obeys the ranges in the table above, and duplicate modes,
   quests or objectives are rejected.

A rejected file writes nothing. `ProgressExportDocument.parse` is the single
validation gate; the importer re-parses programmatically built documents before
opening its transaction.

### Documented error messages

| Scenario | `ProgressFormatErrorCode` | Message |
|---|---|---|
| Truncated or invalid JSON | `malformedJson` | `The file is not a valid progress export: the JSON could not be parsed.` |
| Top level not an object | `malformedJson` | `The file is not a valid progress export: the top level must be a JSON object.` |
| Wrong `format` | `wrongFormat` | `The file is not a valid progress export: the format marker is missing or unknown.` |
| Newer version | `newerVersion` | `This progress file uses format version N, but this app supports up to 1. Update the app to import it.` |
| Old/unsupported version | `unsupportedVersion` | `This progress file uses unsupported format version N.` |
| Missing/malformed checksum | `badChecksum` | `The file is not a valid progress export: the checksum is missing or malformed.` |
| Checksum mismatch | `badChecksum` | `The file is not a valid progress export: the checksum does not match its contents.` |
| Level out of range | `invalidValue` | `The file is not a valid progress export: playerLevel must be between 1 and 99.` |
| Count out of range | `invalidValue` | `The file is not a valid progress export: count must be an integer between 0 and 1000000.` |
| Unknown quest state | `invalidValue` | `The file is not a valid progress export: state must be one of in-progress, completed, failed.` |
| Duplicate quest/objective | `invalidValue` | `The file is not a valid progress export: duplicate ...` |

The checked-in `invalid-bad-checksum.json` fixture fails with the checksum
mismatch message above. Tests assert the exact sentence.

## Preview, merge and replace

Import is never applied automatically:

* **Preview** (`ProgressImporter.preview`) reports the profile count, quest
  state count, objective count, how many rows are new, and how many conflict
  with stored values. It writes nothing.
* **Merge** is the default and non-destructive. Missing quest states are added.
  A conflicting quest state keeps the stored value unless the user picks
  "use file" for that quest. Objective counts merge to the higher value and are
  never lowered. The player level becomes the higher of the stored and imported
  levels.
* **Replace** discards the target profile's progress and writes exactly the
  file's rows, inside the same transaction. The UI asks for a second
  confirmation before this destructive mode runs.

The target is always the profile of the same game mode. A mode with no stored
profile is created. Other modes are not touched.

## Atomicity

Application is one database transaction. A failure before commit — including
the injected failure used by the tests — rolls back the profile facts, the
quest rows and any profile created by the import. The previous state remains
readable and the user can retry.

## Recovery

If an import fails validation, nothing changed: fix the file and import again.
If the file is valid but the wrong progress was applied, import a previously
exported backup. If the app refuses to start, the database is left untouched
(see `docs/schema.md` and `docs/profiles.md`); export from the retained copy is
the next step.

### Hand editing and recomputing the checksum

Edit `profiles` with any text editor, then recompute `checksum`. This Python
snippet matches the Dart canonical encoder for this format:

```python
import hashlib, json

path = "progress.json"
doc = json.load(open(path, encoding="utf-8"))
doc.pop("checksum", None)
canonical = json.dumps(doc, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
doc["checksum"] = "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()
with open(path, "w", encoding="utf-8") as out:
    json.dump(doc, out, indent=2)
    out.write("\n")
```

Forgetting this step produces the documented checksum-mismatch error, which is
intentional: the checksum is an integrity check, not a signature.
