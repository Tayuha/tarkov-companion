# Tarkov Companion — Flutter client

The desktop client for Tarkov Companion. Windows is the launch target; Linux is the development
host; Android stays buildable for a later release.

## Toolchain

- Flutter 3.50.1 (stable channel)
- Dart 3.14.0
- Project constraint: `sdk: ^3.14.0`

Platform folders for `windows`, `linux`, and `android` are checked in.

## Linux (development host)

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d linux
flutter build linux --debug
```

The Linux debug bundle is written to `build/linux/x64/debug/bundle/`.

## Windows (CI only)

Windows builds are verified in GitHub Actions because the development host is Linux. The `app` job in
`.github/workflows/ci.yml` runs on a `windows-latest` runner pinned to Flutter 3.50.1 and executes
`flutter pub get`, `flutter analyze`, `flutter test`, and `flutter build windows --debug`. The Windows
runner sources are generated and tracked, but they cannot be compiled or launched locally. On a Windows
machine:

```powershell
flutter pub get
flutter test
flutter run -d windows
flutter build windows --debug
```

## Package structure

`app/pubspec.yaml` is the root of a Dart pub workspace. All four packages resolve against one lockfile
(`app/pubspec.lock`); the package folders do not have their own lockfiles.

```
app/                          Flutter shell: UI composition, navigation, platform wiring
  lib/
  packages/
    core/                     tarkov_companion_core   pure Dart primitives, no dependencies
    data/                     tarkov_companion_data   bundles, drift/SQLite schema, repositories
    features/                 tarkov_companion_features  Flutter feature modules
```

Dependency rules, enforced by `tool/check_architecture.dart`, a unit test, and CI:

| Package | May import | Must not import |
|---|---|---|
| `core` | `core` | Flutter, `dart:ui`, `data`, `features`, `app` |
| `data` | `core`, `data` | Flutter, `dart:ui`, `features`, `app` |
| `features` | `core`, `data`, `features` | `app` |
| `app` | `core`, `data`, `features`, `app` | — (the shell composes everything) |

No package may import `app`, no feature may import another feature (there is only one features package so
far), and relative imports may not cross a package's `lib/` boundary. Use `package:` imports across
packages.

Run the checker from `app/`:

```bash
dart run tool/check_architecture.dart
```

It scans `lib/` and `packages/*/lib/`, prints every violation as `file:line: directive 'uri': reason`, and
exits 1 on failure. The rule engine is a pure function over source text; `test/check_architecture_test.dart`
proves that a core-to-data import, a data-to-features import, a features-to-app import, and a
cross-package relative import (among others) are each rejected.

The app's own tests run with `flutter test`. The package tests run from `app/` too:

```bash
dart test packages/core
dart test packages/data
flutter test packages/features
```

## Local database

`tarkov_companion_data` owns persistence: the drift schema, the FTS5 item index, and the connection
factory. Game data (`items`, `tasks`, ...) is replaceable and written by bundle ingestion; player data
(`profiles`, `questProgress`, ...) is durable and has **no foreign key onto game data**, so a dataset
refresh cannot delete progress. `docs/schema.md` documents the split, the WAL/FTS setup, and the
no-cascade rule.

Price age is separate from catalog age: `items.priceObservedAt` stores the bundle's
`price.observedAt`, and `FreshnessPolicy` / `ItemsRepository.priceFreshness` label it fresh, stale or
unknown using the `dataFreshnessHours` setting. The rule (including the strict boundary and the UI
obligation to show the observation time) is documented in [`docs/freshness.md`](../docs/freshness.md).

Open the file through `openAppDatabase` (`lib/src/database/migration_runner.dart`). It reads
`user_version` before drift starts, copies an older database to `backups/` with a WAL-safe
`VACUUM INTO` (retaining the newest 3), and returns either `DatabaseOpened` or a read-only
`DatabaseRecovery`. A failed migration never deletes or auto-restores the original; recovery is restored
only by an explicit `restoreFromBackup` user action.

SQLite itself is bundled by `package:sqlite3` 3.x through Dart build hooks — no plugin or system library,
and no `sqlite3_flutter_libs`.

## Ingestion benchmark

A `benchmark`-tagged test ingests the full published items dataset and asserts
the 10 MiB compressed budget, the record counts, FTS, an ingest time budget and
a coarse RSS ceiling. It runs on the Windows CI runner; the normal Linux suite
excludes the tag. Measured numbers, budget rationale and fixture provenance are
in [`docs/benchmark.md`](../docs/benchmark.md).

```bash
cd app
dart test packages/data -t benchmark -j 1
```

## Bundle manifests and dataset state

`tarkov_companion_data` parses the public manifest contract (`docs/data-bundles.md`) from decoded JSON.
The sync layer owns HTTP; the data package only validates and models the document:

```dart
final manifest = BundleManifest.parse(jsonDecode(responseBody));
final compatibility = manifest.checkCompatibility();
if (!compatibility.isCompatible) {
  // Keep the current database and surface compatibility.reason.
}
```

`BundleManifest.parse` validates every required field (`manifestVersion`, both schema versions, mode,
`generatedAt`, source, datasets, totals and `skipped`) and rejects unsafe dataset paths, malformed
SHA-256 values, duplicate datasets and non-positive versions. A failure is a `ManifestFormatException`
whose `path` names the offending field (`datasets[0].path`), so it can be logged without dumping the
document.

The versions the client implements live in `BundleContract`:

| Constant | Value | Meaning |
|---|---|---|
| `manifestVersion` | 1 | Manifest document shape the parser understands |
| `supportedBundleSchemaVersion` | 1 | Newest bundle layout accepted |
| `appDataSchemaVersion` | 1 | Newest dataset record schema ingestible |

`checkCompatibility` applies the rule from `docs/data-bundles.md`:
`bundleSchemaVersion <= supportedBundleSchemaVersion` and
`minAppSchemaVersion <= appDataSchemaVersion`. It returns:

| Status | When |
|---|---|
| `compatible` | Both conditions hold; an older bundle version is accepted |
| `bundleUnsupported` | `bundleSchemaVersion` is newer than the client supports |
| `appUpdateRequired` | `minAppSchemaVersion` needs a newer app data schema |

`DatasetStateRepository` is the only writer of `datasetState` bookkeeping:

- `appliedForMode(mode)` returns the applied checksum, schema version, record count, `appliedAt` and
  upstream timestamp per dataset.
- `recordApplied(dataset, mode: ..., appliedAt: ...)` returns `inserted`, `updated` or `unchanged`.
  The same checksum + schema version + record count is `unchanged` and performs no write, so `appliedAt`
  never moves on a no-op. Source metadata (ETag, timestamps, sizes) is diagnostic and does not count as
  a change.
- A dataset whose `schemaVersion` is newer than `BundleContract.appDataSchemaVersion` is refused with a
  `DatasetApplyRejected` and nothing is written, even if a row already exists.
- `isCurrent` and `clearMode` support the “download only changed datasets” and future full-refresh
  flows.

Manifest fetching (task 4.1) is implemented in `src/sync/`:
`ManifestFetcher` sends the stable per-mode URL with `If-None-Match` /
`If-Modified-Since`, and `ManifestRepository` caches the raw document in
`remoteManifest` with the last-check and last-change times. A `304` returns the
cached manifest and downloads nothing. `DatasetDownloader` (task 4.2) resolves a
dataset path against the manifest, streams it to `<destination>.part` through
`AllowlistedHttpClient.send`, reports monotonic progress, supports cancellation,
verifies `compressedBytes` and SHA-256, and only then renames the file over the
previous dataset. `JsonlLineReader` and `DatasetIngestor` (task 4.3) then stream
the zstd frame with `archive`'s pure-Dart decoder, parse one JSON record per
line, and replace the dataset in one transaction: delete the dataset's rows,
batch-insert 500 at a time, verify the line count, write `datasetState`, commit.
A malformed line, decompression failure or count mismatch rolls everything back
and leaves the previous dataset and version readable. The flow, cache fields,
download/atomic-replace rules, kind routing, transaction and typed failures are
documented in [`docs/client-sync.md`](../docs/client-sync.md).

`SyncScheduler` (task 4.6) decides *when* a check may run. It is pure Dart with
injected settings, clock, timers, network and visibility monitors, and a
`SyncRunner`; it never touches a platform channel. Automatic checks require the
auto-update preference, the foreground, connectivity and an unmetered
connection unless the user allows metered updates; they respect the 6-hour
interval and a 15/30/60-minute failure backoff. Network and visibility changes
trigger a due check immediately. The full policy table, backoff, and the
Flutter-shell wiring that will supply real monitors are documented in
[`docs/sync-scheduler.md`](../docs/sync-scheduler.md).

The remaining manifest work is pure data: the parser and compatibility check
perform no I/O. The tests parse
`packages/data/test/fixtures/manifest-regular.json`, a real
`data-regular-latest` manifest trimmed to `items` and `tasks` (provenance in
`packages/data/test/fixtures/README.md`), without fetching anything.

Regenerate the drift code after changing a table (the generated file is committed; CI does not run
codegen):

```bash
cd packages/data
dart run build_runner build
UPDATE_GOLDENS=1 dart test        # rewrites test/goldens/schema.sql
```

## App settings

`SettingsRepository` in `tarkov_companion_data` stores typed preferences in the
`appSettings` table: the active profile, automatic update checks, metered
downloads, and the data freshness threshold. Values are JSON-encoded strings
under a `settings.` prefix, defaults apply to missing keys, and corrupt values
fall back to the default with a warning instead of throwing. Settings are
local-only and hold no progress or secrets. The keys, defaults, ranges, and
reset semantics are documented in [`docs/settings.md`](../docs/settings.md).

## Network access

The client is local-first and sends no telemetry or analytics. Every request goes through
`AllowlistedHttpClient` in `tarkov_companion_data`, which permits only HTTPS requests to a documented set
of hosts (`github.com` and its release-asset CDN hosts for bundles, `assets.tarkov.dev` for images),
re-validates every redirect hop, and relies on `dart:io` certificate validation without any insecure
override. The policy, rationale, redirect rules, TLS stance, and typed errors are documented in
[`docs/network.md`](../docs/network.md).

## Local diagnostics

`tarkov_companion_data` writes rotating, line-delimited JSON logs under the shell-provided log
directory: `app.log` plus `app.1.log` … `app.4.log`, 1 MiB each by default, with the oldest file dropped.
Exporting produces one ZIP containing the log files under `logs/` and a `metadata.json` with the export
time and app version. Logging is best effort — a broken sink never throws — and nothing is uploaded
automatically. The guarantees, the fields, what is deliberately never logged, and the archive layout are
documented in [`docs/logging.md`](../docs/logging.md).

## Adding dependencies

Keep the dependency set minimal. Every runtime package must work on Windows and stay compatible
with Android/iOS later; prefer pure-Dart packages so logic remains testable without a UI.
