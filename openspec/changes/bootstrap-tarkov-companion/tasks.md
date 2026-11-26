# Tasks

## 1. Project scaffolding

- [ ] 1.1 Create the monorepo layout (`app/`, `pipeline/`, `docs/`, `test/fixtures/`) with a root README that explains each directory, verified by `tree -L 2` matching the documented layout
- [ ] 1.2 Add MIT `LICENSE`, `NOTICE` with tarkov.dev attribution and trademark disclaimer, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, and `SECURITY.md`, verified by every file referenced from README resolving and `LICENSE` matching the OSI MIT text
- [ ] 1.3 Add `.gitignore`, `.editorconfig`, `.gitattributes`, and `dart format`/`prettier` configuration, verified by a clean checkout producing no formatting diff after running both formatters
- [x] 1.4 Create the Flutter project in `app/` with Windows, Linux, and Android targets, verified by `flutter config` listing the desktop targets, `flutter analyze` and `flutter test` passing, and `flutter build linux --debug` succeeding locally; the Windows debug build is verified by task 1.6 CI on a `windows-latest` runner because the development host is Linux
- [x] 1.5 Create the TypeScript pipeline in `pipeline/` with strict `tsconfig`, linting, and a `npm test` runner, verified by `npm run lint && npm test` passing with one placeholder test
- [x] 1.6 Add `.github/workflows/ci.yml` running app analyze/test, pipeline lint/test, and a Windows debug build, verified by the workflow succeeding on the `main` branch (push or dispatch) and on pull requests

## 2. Data pipeline

- [x] 2.1 Implement the localization resolver (JSONPath subset incl. recursive descent and key unions, dictionary lookup, stale/missing diagnostics) plus the fetch helper and CLI, verified by `npm test` covering 25,016 item and 3,642 task strings resolved with zero missing keys and zero unparsable pointers
- [x] 2.2 Capture and commit trimmed upstream fixtures per dataset and game mode under `test/fixtures/upstream/`, verified by fixtures staying under 2 MB total and containing every field the schemas require
- [x] 2.3 Define Zod schemas for each upstream dataset (items, tasks, traders, hideout, crafts, barters, maps) from the captured fixtures, verified by schema tests that accept recorded payloads and reject mutated payloads
- [x] 2.4 Extend the upstream fetcher with ETag/Last-Modified conditional requests and per-dataset checksum caching, verified by unit tests for 200, 304, 429, and 500 responses
- [x] 2.5 Implement normalization from the localized upstream shape to the bundle JSONL shape (stable keys, resolved references, price fields, objective types), verified by golden-file tests comparing normalized output for the fixtures
- [x] 2.6 Implement the bundle writer producing `manifest.json` and per-dataset `.jsonl.zst` files with SHA-256 checksums, sizes, schema versions, and source timestamps, verified by a test that rebuilds the same fixture twice and produces identical checksums
- [x] 2.7 Implement dataset version comparison so unchanged upstream content publishes nothing, verified by a test where the second run over identical input emits no bundle and exits successfully
- [x] 2.8 Implement bundle publication to GitHub Releases with an idempotent upload and a stable `latest` manifest pointer, verified by a dry-run mode test and one manual run against a test release
- [x] 2.9 Add `.github/workflows/data-sync.yml` running every 6 hours with concurrency control and failure notification, verified by a manual `workflow_dispatch` run publishing or correctly skipping a release
- [x] 2.10 Document the pipeline contract (bundle layout, schema versions, manifest fields, localization) in `docs/data-bundles.md`, verified by a reader being able to hand-build a valid bundle from the document and pass a validation command
- [x] 2.11 Add a pipeline check that fails on missing translation coverage or compressed bundle size above the 10 MB budget, verified by tests with a missing-key fixture and an oversized synthetic dataset both failing the build

## 3. Client foundation

- [x] 3.1 Establish the Dart package structure (`core`, `data`, `features`, `app`) with dependency rules enforced by a test or lint, verified by an import-boundary check failing on a deliberate violation
- [x] 3.2 Implement the drift database with game-data and player-data tables, WAL mode, and no cascading foreign keys from player to game data, verified by migration and schema snapshot tests
- [ ] 3.3 Implement the versioned migration runner with a pre-migration database copy and read-only recovery mode, verified by tests covering a successful migration and a deliberately failing migration that preserves the original file
- [ ] 3.4 Implement `dataset_state` bookkeeping (applied version, checksum, applied_at) and the manifest model, verified by unit tests for first apply, idempotent re-apply, and newer-schema refusal
- [ ] 3.5 Implement an HTTP client confined to a documented host allowlist with certificate validation and no redirects to unknown hosts, verified by tests that a disallowed host is rejected before any request is sent
- [ ] 3.6 Implement rotating local logging plus an export-logs action, verified by a test that exceeds the rotation threshold and asserts old entries are dropped and the exported archive opens
- [ ] 3.7 Implement app settings storage (active profile, auto-update preference, metered behavior, data freshness threshold) with defaults, verified by tests for defaults, persistence across restart, and reset

## 4. Sync and ingestion

- [ ] 4.1 Implement manifest fetching with ETag conditional requests and a last-check timestamp, verified by a test asserting a 304 response performs no dataset download
- [ ] 4.2 Implement dataset download with streaming, progress reporting, cancellation, and SHA-256 verification, verified by tests for a valid file, a corrupted file, and a cancelled mid-download
- [ ] 4.3 Implement streaming JSONL decompression and batched ingestion in a single transaction per dataset, verified by an integration test ingesting the item fixture and asserting row counts and applied version
- [ ] 4.4 Implement ingestion failure rollback so a failed dataset leaves prior rows and version intact, verified by a test that injects a failure after partial insert and asserts rollback
- [ ] 4.5 Implement FTS5 search indexing over item name, shortName, and normalizedName with diacritic folding, refreshed after items ingestion, verified by search tests including an accented name matched by an unaccented query
- [ ] 4.6 Implement the background update scheduler honoring the auto-update preference, metered connections, and app foreground state, verified by fake-clock tests for each preference combination
- [ ] 4.7 Implement stale-data labelling based on the newest price observation, verified by tests at the threshold boundary showing fresh vs stale states
- [ ] 4.8 Add an ingestion performance benchmark on the full item dataset asserting the 10 MB compressed and bounded-memory budgets, verified by the benchmark running in CI on the Windows runner
- [ ] 4.9 Document the sync protocol, failure semantics, and offline behavior in `docs/sync.md`, verified by each documented state being reproducible from the sync test suite

## 5. Item catalog

- [ ] 5.1 Implement the catalog query layer with pagination, category/type/flea filters, and sorting, verified by query tests covering each filter alone and in combination
- [ ] 5.2 Build the catalog screen with virtualized rows, debounced search, active-filter chips, and a reset action, verified by a widget test covering typing, filtering, empty state, and reset
- [ ] 5.3 Implement the item detail view with type-specific property rendering and omission of non-applicable properties, verified by golden widget tests for a weapon, ammunition, armor, and a barter-only item
- [ ] 5.4 Implement acquisition and disposition sections (trader buy/sell, barter, craft, quest requirement links), verified by widget tests asserting each section renders from fixture relationships
- [ ] 5.5 Implement price presentation with source, observation time, 48-hour direction, and explicit missing-data states, verified by widget tests for complete, missing-flea, and zero-price fixtures
- [ ] 5.6 Implement the disk-backed image cache with lazy loading, placeholder fallback, and a size budget, verified by tests for cache hit offline, failed fetch, and eviction at the budget
- [ ] 5.7 Implement on-demand price history fetch, caching with TTL, and the chart view including the offline-without-cache state, verified by tests for fetch, cache hit, TTL expiry, and offline miss
- [ ] 5.8 Implement item deep links by game identifier with resolved and removed-item states, verified by tests opening a known id and a deleted id against a fixture dataset
- [ ] 5.9 Add a catalog performance test asserting p95 query latency under 50 ms and initial render under 1.5 s with the full fixture set, verified by the test running in CI

## 6. Quest tracker

- [ ] 6.1 Implement the quest query layer with search, trader/level/map/state filters, and pagination, verified by query tests for each filter and their intersections
- [ ] 6.2 Build the quest catalog screen with state badges and filter controls, verified by widget tests covering search, filtering, and empty results
- [ ] 6.3 Implement the availability engine deriving locked/available/in-progress/completed from prerequisites, level, and progress, verified by table-driven unit tests including chains of prerequisites and cycles in malformed data
- [ ] 6.4 Implement the locked-reason model and its presentation on quests, verified by widget tests naming level, prerequisite quest, and trader loyalty reasons
- [ ] 6.5 Build the quest detail view with objectives, requirements, rewards, unlocks, maps, and wiki link, verified by golden widget tests for quests with item, kill, and visit objectives
- [ ] 6.6 Implement quest state transitions with immediate persistence and dependency recomputation, verified by integration tests for complete, revert, and unaffected-sibling cases
- [ ] 6.7 Implement objective-level counters with derived quest completion and a confirmed manual override, verified by tests for partial progress, derived completion, and override without altering counts
- [ ] 6.8 Implement separation of progress that references quests missing from the active dataset, verified by a test loading a profile that references a removed quest and asserting it is listed as unavailable and excluded from dependency math
- [ ] 6.9 Implement the available-quests view with selectable ordering and an explanatory empty state, verified by widget tests for a populated list and for a profile with nothing available
- [ ] 6.10 Implement game-mode scoping so the tracker reads only the active mode's quest dataset, verified by a test asserting a PvE-only quest is absent under the regular profile
- [ ] 6.11 Document quest state semantics and override behavior in `docs/quest-tracking.md`, verified by the documented state table matching the implementation tests

## 7. Profiles and portability

- [ ] 7.1 Implement per-mode profile creation, activation, and switching with a single active profile invariant, verified by tests for first launch, explicit creation, and switching
- [ ] 7.2 Implement editable profile facts (player level, and faction if retained) with immediate re-derivation, verified by a test that a level change unlocks a quest without restart
- [ ] 7.3 Implement profile reset and deletion with confirmation and post-delete activation of another profile, verified by integration tests including deleting the last profile
- [ ] 7.4 Implement the export document writer with canonical JSON and checksum, verified by a golden-file test and a checksum stability test across key ordering
- [ ] 7.5 Implement export through the platform file picker for the active profile and all profiles, verified by an integration test writing to a temporary directory and re-reading the file
- [ ] 7.6 Implement import validation (format, version, checksum, value ranges) rejecting without writes, verified by tests for truncated JSON, wrong format, newer version, and bad checksum
- [ ] 7.7 Implement the import preview with explicit replace/merge selection and non-destructive default, verified by widget tests for preview counts, cancel, replace, and merge conflict resolution
- [ ] 7.8 Implement transactional import application and rollback on failure, verified by a test injecting a write failure and asserting the profile is unchanged
- [ ] 7.9 Add a cross-format portability test importing a fixture export produced by the documented format, verified by the test running on both Windows and Linux CI runners
- [ ] 7.10 Document the progress file format and recovery steps in `docs/progress-format.md`, verified by a hand-edited fixture importing successfully and an invalid one failing with the documented message

## 8. Desktop shell

- [ ] 8.1 Implement the first-run bootstrap flow with size estimate, progress, cancel, retry, and resume, verified by widget tests for each state and an integration test against a local mock manifest server
- [ ] 8.2 Implement non-blocking startup that renders from the last dataset before any network call, verified by a test that delays the manifest response and asserts the first frame still renders
- [ ] 8.3 Implement update check controls (schedule, manual check, last check time/outcome) with non-modal indicators, verified by widget tests for each outcome and preference combination
- [ ] 8.4 Implement offline and upstream-error states across catalog, quests, and history views with retry, verified by widget tests with a failing network layer
- [ ] 8.5 Implement window geometry persistence with display clamping and a minimum size, verified by tests for restored geometry and an off-screen saved position
- [ ] 8.6 Implement single-instance focusing on Windows, verified by a manual test launching twice and observing one window is focused
- [ ] 8.7 Implement keyboard navigation and visible focus for the catalog and quest lists, verified by widget tests driving focus traversal without pointer input
- [ ] 8.8 Implement the about screen showing app version, data bundle version, dataset age, license, and attribution, verified by a golden widget test
- [ ] 8.9 Build the per-user Windows installer in CI with an uninstaller and version metadata, verified by installing on a clean Windows VM without administrator rights and launching the app
- [ ] 8.10 Publish installer checksums with release notes that state signing status, verified by a release dry run producing the checksum file and the expected note text

## 9. Integration and release readiness

- [ ] 9.1 Add an end-to-end test covering first run, catalog browse, item detail, quest completion, export, and re-import, verified by the test passing against the fixture-backed build
- [ ] 9.2 Verify offline behavior end to end with the network disabled after an initial sync, verified by a manual checklist run on a clean Windows VM covering every primary screen
- [ ] 9.3 Verify the read-only recovery path by corrupting a copy of the database, verified by the app opening in recovery mode, offering export, and refusing writes
- [ ] 9.4 Audit all network destinations against the documented allowlist, verified by a captured-request review with no hosts outside the list
- [ ] 9.5 Finalize README with screenshots, build-from-source steps, data attribution, and contribution paths, verified by a contributor following it on a clean machine
- [ ] 9.6 Tag `v0.1.0` and publish the first Windows release with bundles, installer, checksums, and release notes, verified by downloading the artifacts from the public release page and installing
- [ ] 9.7 Add issue and pull-request templates plus a roadmap issue, verified by opening a test issue that renders both templates

## Workflow follow-up

- Archive `bootstrap-tarkov-companion` after the v0.1.0 release is verified.
- Open a follow-up change for interactive maps and hideout/craft calculators.
- Open a follow-up change for the visual design system once layout exploration is done.
