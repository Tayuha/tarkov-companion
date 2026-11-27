# Testing

The suite has three layers:

| Layer | Location | Command |
| --- | --- | --- |
| Unit and widget | `app/test/`, `app/packages/*/test/` | `cd app && flutter test` |
| End-to-end widget flow | `app/test/e2e/` | `cd app && flutter test test/e2e` |
| Pipeline | `pipeline/` | `cd pipeline && npm test` |

## End-to-end flow

```bash
cd app
flutter test test/e2e/first_run_round_trip_test.dart
```

`test/e2e/first_run_round_trip_test.dart` drives the real widgets against a real
file-backed SQLite database:

1. **First run** — `AppRoot` shows the first-run gate. A fake sync service
   applies the committed bundle fixture through the production
   `DatasetIngestor`, so the estimate, Start action, and post-run shell all run
   as they do in the app.
2. **Catalog browse** — `HomeShell` / `CatalogScreen` search narrows the fixture
   items and opens `ItemDetailScreen` for the Colt M4A1.
3. **Quest progress** — the Quests tab opens `QuestDetailScreen` for Debut; the
   objective counter is raised to its required count and the quest is marked
   completed. Because the objectives are satisfied, this path does not take the
   manual-override dialog.
4. **Profile fact** — the Profiles tab changes the regular profile to level 37.
5. **Export** — the active profile is exported through the
   `DirectoryProgressFilePicker` into the temp root. The test re-parses the JSON
   and asserts the level, quest state, and objective count.
6. **Re-import** — the profile is deleted, then the exported file is imported
   through the real preview and merge path. The test asserts the profile level,
   active profile, quest state, and objective count are restored.

The test runs headless: there is no `integration_test` device, display, network
call, or real user data directory. The temporary root is created with
`createTempSync` and removed in the test's teardown; the database is
`<temp>/db/tarkov_companion.sqlite`, never `~/.local/share/tarkov_companion`.

### Why a widget-level end-to-end test

`integration_test` needs a device or desktop display, which the CI runners do
not provide. The app shell and the feature screens are plain widgets, so the
test drives `AppRoot`, `HomeShell`, `CatalogScreen`, `ItemDetailScreen`,
`QuestDetailScreen`, and `ProfilesScreen` directly with a real database and a
real fixture bundle. The only faked piece is the sync transport; the ingestion,
queries, widgets, and export/import code are production code.

Widget tests use fake time. File and SQLite work started by a button callback
therefore gets one short real event-loop turn (`tester.runAsync`) before
`pumpAndSettle` advances the fake clock; this is not an arbitrary UI sleep.
Exports and imports are awaited by polling the same real event loop, with a
bounded timeout instead of a fixed delay.

### Seams used

The native file dialog cannot run headlessly. `AppRoot` and `HomeShell` accept
an optional `ProgressFilePicker` that is forwarded to `ProfilesScreen`; the
production default is `PlatformProgressFilePicker`, and the test passes
`DirectoryProgressFilePicker`. No feature screen or data query changed.

## Fixture layout

| Path | Purpose |
| --- | --- |
| `app/packages/data/test/fixtures/bundle/` | The end-to-end bundle: `manifest.json`, `items.jsonl.zst`, `tasks.jsonl.zst`. The fake sync ingests these committed files. |
| `app/packages/data/test/fixtures/` | Package-level manifest and database test fixtures. |
| `test/fixtures/normalized/` | The full pipeline-produced corpus (items, tasks, traders, maps, hideout, crafts, barters) used by data and feature tests. |
| `test/fixtures/upstream/` | Trimmed upstream payloads for pipeline schema tests. |
| `app/test/support/e2e_environment.dart` | Temp installation, production-shaped session, and the fixture-backed `SyncService`. |

The bundle fixture resolves from the working directory, so `flutter test` from
`app/` and an IDE run from the repository root both find it. It is test-only
data and is never copied into a release bundle.

## Remaining manual checks

These are not covered by the automated flow and stay on the release checklist:

- **Offline toggle** — disable the network after the first sync, then walk the
  catalog, item detail, quests, and profiles. The automated flow never opens a
  socket, so it cannot exercise the offline status strip or retry controls.
- **Read-only recovery** — corrupt a copy of the database and confirm the app
  opens in recovery mode, offers export, and refuses writes.
- **Clean-machine install** — download the release artifacts, verify checksums,
  first-run sync, browse, restart offline, and uninstall. See
  [`linux-package.md`](linux-package.md) and [`release.md`](release.md).
- **Native surfaces** — the platform file dialog, window geometry/single
  instance, and OS-level keyboard focus are either stubbed by the picker seam or
  intentionally outside the widget test.
