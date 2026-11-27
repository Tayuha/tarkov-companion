# Release verification

Release gate: **Linux 0.1.0 preview**
Version: `0.1.0+1` (`app/pubspec.yaml`)
Checklist prepared: **2026-11-27**
Commit under test: fill with `git rev-parse --short HEAD` at the gate
Tester and environment: fill before running (distribution, kernel, display server, GPU, network device)

Result legend: `☐ pass` / `☐ fail`. An empty box means the step has not been run. This page records the
release-gate checks for tasks **9.2** (offline), **9.3** (recovery), **9.4** (network audit), and **9.5**
(README walkthrough). No manual result is claimed here.

## Automated checks run for this document

These commands are read-only or analysis-only and were run on 2026-11-27 in the
`docs-release-readiness` worktree.

| Check | Command | Result |
|---|---|---|
| Shell syntax | `bash -n scripts/audit-network.sh scripts/verify-offline.sh` | **PASS** |
| Static network allowlist audit | `bash scripts/audit-network.sh` | **PASS** — 4 allowlist hosts, 4 documented hosts, observed literals are `github.com` (request) and `tarkov.dev` (About text only). |
| OpenSpec validation | `openspec validate bootstrap-tarkov-companion --strict` | **PASS** |

The static audit does not replace a captured-request run. The app tests and packaging smoke test were not
run in this documentation pass; run them on the gate machine:

```bash
cd app && flutter analyze && flutter test
cd .. && bash scripts/package-linux.sh
```

## Offline checklist (task 9.2)

### Preconditions

- A clean Linux environment with the AppImage or a built bundle.
- One completed online sync, so `datasetState` has applied rows and the item/quest lists render.
- No second instance running. Single-instance focusing is part of the shell, not this check.
- Networking disabled **without root and without firewall changes**. Use one of:
  - `unshare -n -- <app>` (unprivileged network namespace, when the host permits it);
  - `unshare -Urn -- <app>` (user namespace mapping, when only that variant is permitted);
  - the desktop network menu (turn Wi-Fi/Ethernet off), then launch normally.

`scripts/verify-offline.sh` reports which namespace form works and can launch the app:

```bash
bash scripts/verify-offline.sh          # read-only preflight and the manual sequence
bash scripts/verify-offline.sh --launch # start the app with no network namespace
```

Do not run it with `sudo`, and do not add `iptables`/`nftables` rules.

### Screens

Record the exact window title, any status strip text, and the result for each row.

| # | Check | Expected observation | Result |
|---|---|---|---|
| O1 | Start the app with networking already disabled. | The window opens from the local database. No first-run gate when applied data exists. | ☐ pass ☐ fail |
| O2 | Items tab. | Saved rows render. Search, category filter, and sorting still work against SQLite. | ☐ pass ☐ fail |
| O3 | Items tab status. | Non-blocking strip titled **Offline** with “Showing saved data. The update check could not reach the network; retry when a connection is available.” Saved rows stay visible. | ☐ pass ☐ fail |
| O4 | Open an item detail. | Header, type-specific stats, trader/flea prices, and quest use render from the database. Placeholder artwork is acceptable in this preview. | ☐ pass ☐ fail |
| O5 | Item detail price history. | Either cached points render with “Showing cached history; the source could not be refreshed.”, or the panel says “Price history unavailable offline. No cached history exists for this item; it will load on the next online visit.” | ☐ pass ☐ fail |
| O6 | Quests tab. | Saved quest list and the Catalog/Available views render without a blank screen. | ☐ pass ☐ fail |
| O7 | Quests tab with no saved view results. | Empty state says “No quests are saved yet.” or “No saved quests and the update failed.” with **Retry update**; the rest of the tab remains usable. | ☐ pass ☐ fail |
| O8 | Open a quest detail and complete an objective. | Detail renders from the database; the objective toggle changes state and survives a tab switch. | ☐ pass ☐ fail |
| O9 | Restart while still offline. | The completed objective and the item/quest data are still present. No recovery screen. | ☐ pass ☐ fail |
| O10 | Profiles tab: activate a profile, export it, then re-import it. | All three actions work with networking off because they use local files and SQLite. The confirmation names the written path. | ☐ pass ☐ fail |
| O11 | About screen from the footer. | App version `0.1.0`, bundle version/age, dataset counts, MIT licence, tarkov.dev attribution, and the no-bundled-game-art statement render. | ☐ pass ☐ fail |
| O12 | Footer update control. | Last outcome is **Offline** or **Last update check failed**; **Check now** returns to idle without a crash or a dialog that blocks browsing. | ☐ pass ☐ fail |
| O13 | Image cache. | Open an item with artwork: the image loads through `assets.tarkov.dev` and a file appears under `<data>/cache/images`. Restart offline and reopen the item: the same image loads from disk without a request. `du -sh` stays at or below 32 MiB. | ☐ pass ☐ fail |
| O14 | Reconnect and press **Retry** / **Check now**. | The check reaches the manifest, reports the current data, and the offline strip clears. No data is lost. | ☐ pass ☐ fail |

### First run with no network

Use a throwaway data root so the real profile is untouched:

```bash
export XDG_DATA_HOME=/tmp/tc-offline-empty
rm -rf /tmp/tc-offline-empty
mkdir -p /tmp/tc-offline-empty
bash scripts/verify-offline.sh --launch
```

| # | Check | Expected observation | Result |
|---|---|---|---|
| O15 | Launch with an empty data root and no network. | The first-run gate reaches its error state. Heading: **Could not get the game data**. The detail is the typed sync failure, and a **Retry** button is present. | ☐ pass ☐ fail |
| O16 | Press **Retry** while still offline. | The same error state returns; no partial file is reported as installed. | ☐ pass ☐ fail |
| O17 | Restore networking and press **Retry**. | The download starts, progress is shown, and the shell opens after the last dataset is applied. | ☐ pass ☐ fail |

## Network audit (task 9.4)

### Static result

`bash scripts/audit-network.sh` passed. It parses
`NetworkAllowlist.productionHosts` and the *Allowed hosts* table in [`network.md`](network.md), then scans
production Dart sources. The documented and executable lists both contain exactly:

| Host | Purpose |
|---|---|
| `github.com` | Stable manifest URL. |
| `objects.githubusercontent.com` | GitHub release-asset redirect target. |
| `release-assets.githubusercontent.com` | Newer GitHub release-asset redirect target. |
| `assets.tarkov.dev` | Item artwork (cache not wired in the preview shell). |

Only two literal hosts appear in production source: `github.com` in the manifest URL and user agent, and
`tarkov.dev` as About-screen text. The latter is recorded under *Text-only hosts* and is never requested.

### Captured-request review (manual)

Run the first-run sync or **Check now** while capturing connections from the app process. Any packet
capture or proxy is acceptable; record the tool and the destination list. The review passes only when every
destination is one of the four hosts above (redirects included) and no analytics, crash-reporting, or
account endpoint appears.

| # | Check | Expected observation | Result |
|---|---|---|---|
| N1 | Capture a first-run sync or an update check. | Only `github.com`, the two GitHub asset hosts, and optionally `assets.tarkov.dev` appear. | ☐ pass ☐ fail |
| N2 | Inspect request headers and bodies. | `GET` only; no cookies, authorization header, account identifier, or request body. | ☐ pass ☐ fail |
| N3 | Inspect the app after idling. | No periodic request beyond the configured update schedule. No request when no check is due. | ☐ pass ☐ fail |

## Recovery checklist (task 9.3)

The goal is to prove that a damaged database opens read-only, keeps every byte, offers no way to write, and
tells the user what happened. Use a **copy**; never corrupt the real database.

### Setup

```bash
REAL_DB="${XDG_DATA_HOME:-$HOME/.local/share}/tarkov_companion/db/tarkov_companion.sqlite"
RECOVERY_HOME=/tmp/tc-recovery
rm -rf "$RECOVERY_HOME"
mkdir -p "$RECOVERY_HOME/tarkov_companion/db"

# Copy the database and its WAL sidecars, if present.
cp "$REAL_DB" "$RECOVERY_HOME/tarkov_companion/db/tarkov_companion.sqlite"
for sidecar in "$REAL_DB"-wal "$REAL_DB"-shm; do
  [[ -f "$sidecar" ]] && cp "$sidecar" "$RECOVERY_HOME/tarkov_companion/db/"
done

sha256sum "$RECOVERY_HOME/tarkov_companion/db/tarkov_companion.sqlite" \
  > /tmp/tc-recovery-before.sha256

# Corrupt only the copy.
printf 'not a sqlite database\n' \
  > "$RECOVERY_HOME/tarkov_companion/db/tarkov_companion.sqlite"
```

Launch against the throwaway root:

```bash
XDG_DATA_HOME="$RECOVERY_HOME" ./dist/TarkovCompanion-0.1.0-x86_64.AppImage
```

The app bar reads **Tarkov Companion**. The body shows:

- heading: **Local database recovery**;
- message: **The local database could not be opened. It was left untouched and is available read-only.**
  followed by the SQLite failure text (for a non-SQLite file this is a malformed-image or “file is not a
  database” error; the exact SQLite code depends on the build);
- additional text: **No data was deleted. Export and recovery actions arrive in the release-readiness
  task.**

### Checks

| # | Check | Expected observation | Result |
|---|---|---|---|
| R1 | Launch with the corrupt copy. | The recovery screen appears instead of the shell; the app does not crash or create a fresh empty database. | ☐ pass ☐ fail |
| R2 | Read the message. | It contains the heading and sentence above, and names the SQLite failure. | ☐ pass ☐ fail |
| R3 | Look for an export action. | **Expected by task 9.3, currently missing.** The screen has no button; the text says export and recovery actions arrive later. This row fails until the recovery UI gains an export action. | ☐ pass ☐ fail |
| R4 | Try to write through the app. | No write action is offered in recovery. The handle is SQLite `OpenMode.readOnly`; writes fail at the SQLite layer. | ☐ pass ☐ fail |
| R5 | Confirm the copy was not modified. | `cd "$RECOVERY_HOME/tarkov_companion/db" && sha256sum -c /tmp/tc-recovery-before.sha256` reports **OK**. | ☐ pass ☐ fail |
| R6 | Confirm the original database is untouched. | Open the real app normally after the test; it still starts with the previous data. | ☐ pass ☐ fail |
| R7 | Inspect the log. | `grep 'read-only recovery mode' "$RECOVERY_HOME/tarkov_companion/logs/app.log"` finds one JSON line with `path` and `failure` context. | ☐ pass ☐ fail |
| R8 | Confirm no automatic restore happened. | No file under `db/backups/` is newer than the test start, and the corrupt file is still the corrupt file. | ☐ pass ☐ fail |

### Deterministic write-refusal variant (optional)

A byte-corrupt file cannot answer SQL queries, so it cannot demonstrate the “attempt to write a readonly
database” message. A valid SQLite copy with a future schema version triggers the same recovery path and
keeps the file readable:

```bash
DB_COPY="$RECOVERY_HOME/tarkov_companion/db/tarkov_companion.sqlite"
rm -f "$DB_COPY" "$DB_COPY-wal" "$DB_COPY-shm"
cp "$REAL_DB" "$DB_COPY"
sqlite3 "$DB_COPY" 'PRAGMA user_version = 99;'
```

Expected recovery message includes:
**Database schema version 99 is newer than the supported version 5. Refusing to downgrade.**
(The supported version is `AppDatabase.targetSchemaVersion`, currently 5; substitute the current value if it
has moved.)

Then prove the read-only rule at the SQLite layer on the same copy:

```bash
sqlite3 -readonly "$DB_COPY" \
  "INSERT INTO appSettings (key, value) VALUES ('x', 'y');"
```

Expected: an error containing **attempt to write a readonly database**. The app itself does not expose this
command;
the automated equivalent is `app/packages/data/test/migration_runner_test.dart`, which asserts that
`RecoveryDatabase.execute` throws `SqliteException` after a failing migration.

## README walkthrough (task 9.5)

Follow [`README.md`](../README.md) on a clean machine with no Flutter SDK and no prior app data. Record the
result of each step.

| # | Check | Expected observation | Result |
|---|---|---|---|
| D1 | Every screenshot and relative link resolves. | The three preview images load and each linked document exists. | ☐ pass ☐ fail |
| D2 | Install the stated Linux prerequisites and run the build-from-source commands. | `flutter pub get` and `flutter run -d linux` succeed as written. | ☐ pass ☐ fail |
| D3 | Run `bash scripts/package-linux.sh`. | The AppImage and `SHA256SUMS` are produced; `sha256sum -c SHA256SUMS` passes. | ☐ pass ☐ fail |
| D4 | Launch the AppImage and complete first run. | The app opens, syncs, and browses as the README says. | ☐ pass ☐ fail |
| D5 | Check the attribution and privacy statements against the UI and [`NOTICE`](../NOTICE). | They agree: tarkov.dev data, assets.tarkov.dev artwork, no bundled game art, no telemetry. | ☐ pass ☐ fail |

## Known gaps found by this audit

| Gap | Evidence |
|---|---|
| Recovery offers no export or restore action. | `app/lib/src/app_root.dart` renders static recovery text: “Export and recovery actions arrive in the release-readiness task.” Task 9.3 requires an export offer. |
| Price history has no production source. | The published bundle has no history endpoint. `PriceHistoryRepository` is injectable and tested; the detail screen shows the documented unavailable state until a history source is allowlisted. |
| `host_allowlist.dart` still says GitHub hosts an app-update release page. | The client has no URL launcher and no self-updater; this document corrects the claim, but the code comment is out of scope for this change. |

## Sign-off

| Task | Gate | Result |
|---|---|---|
| 9.2 | Offline checklist on a clean Linux environment | ☐ pass ☐ fail |
| 9.3 | Recovery checklist on a corrupt copy | ☐ pass ☐ fail |
| 9.4 | Static audit plus captured-request review | Static ☐ pass · Capture ☐ pass ☐ fail |
| 9.5 | Contributor follows README on a clean machine | ☐ pass ☐ fail |

Do not tick the OpenSpec task boxes until the corresponding manual gate passes and the commit under test is
recorded above.
