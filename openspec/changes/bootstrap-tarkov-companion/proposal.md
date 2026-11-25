# Proposal

## Why

Escape from Tarkov players juggle several community sites to answer everyday questions: what a quest
actually requires, where an item comes from, what it is worth, and what to do next. Those sites are
web-first and assume a connection, while the moments that matter (in raid, between raids, on a second
monitor) are exactly when a fast, offline-capable, keyboard-friendly desktop app is better.

The community API at `json.tarkov.dev` already exposes the full game dataset for free, but it is a raw
bulk feed: a single `/regular/items` response is ~17 MB, `/regular/maps` is ~9 MB, and
`/regular/tasks` is ~2 MB. Any client that calls it directly on launch delivers a slow, bandwidth-heavy
first run and inherits every upstream schema change.

This change establishes the project as an open-source, local-first companion app with a deliberate
data pipeline and a vertical slice (quests + items) that proves the architecture end to end.

## What Changes

- Create a new cross-platform application (Flutter) targeting Windows desktop at launch, with Android
  and iOS kept buildable for later.
- Add an offline-first data layer: a scheduled pipeline normalizes upstream JSON into versioned,
  compressed bundles published as release assets; the client downloads only what changed and keeps a
  local SQLite database as the single read path.
- Add an item catalog: search, filters, item detail with images, trader/flea prices, and price history.
- Add a quest tracker: quest list and detail, objectives, requirements and unlocks, with per-profile
  completion state.
- Add local player profiles: one profile per game mode (PvP, PvE, season), export/import as a portable
  JSON file, and forward-only schema migrations.
- Add a desktop application shell: first-run data bootstrap, background update checks, packaging and
  signing for Windows, and a privacy stance of "no telemetry, no accounts, no network calls beyond data
  and update fetches".
- Add open-source project scaffolding: MIT license, README, contributing guide, code of conduct,
  NOTICE with upstream attribution and a trademark disclaimer, CI for lint/test/build.
- Explicitly out of scope for this change: interactive maps, hideout/craft calculators, barter profit,
  stash OCR, cloud sync, accounts, and any UI visual design system (layout and design are handled in a
  later change).

## Capabilities

### New Capabilities

- `data-sync`: Versioned game-data bundles, delta downloads, integrity verification, freshness policy,
  and offline fallback behavior for the three upstream game modes.
- `item-catalog`: Browsable and searchable item database with filters, item detail, images, trader and
  flea pricing, and price history.
- `task-tracking`: Quest catalog with objectives, requirements, rewards and unlocks, plus per-profile
  quest state transitions and dependency awareness.
- `local-profiles`: Local player profiles scoped to a game mode, portable export/import, data ownership
  guarantees, and schema migration policy.
- `app-shell`: Desktop application lifecycle: first-run bootstrap, data update scheduling, failure and
  offline states, window/platform integration, and release packaging.

### Modified Capabilities

None. This is the initial capability set for the project.

## Impact

- **New code**: Flutter application (`app/`), a Node/TypeScript data pipeline (`pipeline/`), and shared
  fixtures under `packages/` or `data/` as the design decides.
- **External systems**: `json.tarkov.dev` JSON endpoints (read-only), `assets.tarkov.dev` for item
  images, GitHub Releases for bundles and app updates, GitHub Actions for scheduling and CI.
- **Dependencies**: Flutter/Dart, `drift` + SQLite, an HTTP client with ETag support, a compression
  library, and a Windows installer toolchain (MSIX or Inno Setup).
- **Users**: no accounts, no server-side data. Progress lives only on the device until the user exports
  it.
- **Risks**: upstream schema and naming changes, placeholder translations observed in the API
  (`"<id> Name"`), trademark/branding constraints, and Windows code-signing cost.
