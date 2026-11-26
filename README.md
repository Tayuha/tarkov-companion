# Tarkov Companion

[![CI](https://github.com/Tayuha/tarkov-companion/actions/workflows/ci.yml/badge.svg)](https://github.com/Tayuha/tarkov-companion/actions/workflows/ci.yml)
[![Data sync](https://github.com/Tayuha/tarkov-companion/actions/workflows/data-sync.yml/badge.svg)](https://github.com/Tayuha/tarkov-companion/actions/workflows/data-sync.yml)

An open-source, local-first companion app for **Escape from Tarkov**: browse every item, follow the
flea market, and track quest progress — on your machine, offline, without an account.

> **Status: planning.** The architecture and specifications live in
> [`openspec/changes/bootstrap-tarkov-companion/`](openspec/changes/bootstrap-tarkov-companion/).
> The application code is not written yet.

## Why

Community sites are web-first and assume a connection. A companion app should open instantly, work in
raid or between raids with no signal, and keep your progress on your own device.

## What it will do (v0.1)

- **Item catalog** — search and filter all items, inspect type-specific stats, trader and flea prices,
  and price history.
- **Quest tracker** — quests with objectives, requirements, rewards and unlocks; derived
  locked/available/completed state; per-objective progress.
- **Local profiles** — one profile per game mode (PvP, PvE, season), with versioned JSON export/import.
- **Offline-first** — all game data is stored locally and updated incrementally in the background.

Not in v0.1: interactive maps, hideout/craft calculators, barter profit, stash OCR, cloud sync, accounts.

## Architecture at a glance

```
json.tarkov.dev  --(scheduled GitHub Action)-->  normalized JSONL.zst bundles
                                                        |
                                                  GitHub Releases
                                                        |
                                            manifest + changed datasets
                                                        |
                                                        v
                                   Flutter app (Windows, later Android/iOS)
                                       drift/SQLite = single read path
```

The app never calls the upstream API directly and never downloads a prebuilt database. A small
TypeScript pipeline validates and normalizes upstream JSON into versioned bundles; the app verifies each
dataset by SHA-256 and ingests it transactionally into its own schema. See
[`design.md`](openspec/changes/bootstrap-tarkov-companion/design.md) for the full rationale.

## Repository layout

| Path | Purpose |
|---|---|
| `app/` | Flutter client (Windows target at launch) |
| `pipeline/` | Node/TypeScript data pipeline and bundle publisher |
| `test/fixtures/` | Trimmed upstream fixtures used by tests |
| `docs/` | Data bundle contract, sync protocol, local schema, progress format |
| `openspec/` | Specifications, design, and implementation plan |

## Building

Prerequisites: Flutter (stable), Node.js 24+ (the bundle writer uses built-in zstd), Git.

```bash
git clone git@github.com:Tayuha/tarkov-companion.git
cd tarkov-companion

cd pipeline && npm ci && npm test && npm run build
cd ../app && flutter pub get && flutter test && flutter run -d windows
```

The pipeline can run against committed fixtures without network access or secrets:

```bash
cd pipeline && npm run build -- --fixtures ../test/fixtures --out ../dist
```

## Data and attribution

Game data comes from the community-run [tarkov.dev](https://tarkov.dev) API. Item images are served from
`assets.tarkov.dev`. This project is not affiliated with, endorsed by, or sponsored by Battlestate Games.
Escape from Tarkov and related marks are the property of their respective owners. See [`NOTICE`](NOTICE).

## Privacy

No telemetry, no analytics, no accounts. Network requests are limited to a documented allowlist: data
bundle downloads, app update checks, price history, and item images. Player progress never leaves the
device unless the user exports it.

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md). Planning artifacts are managed with
[OpenSpec](https://github.com/Fission-AI/OpenSpec): start from `openspec list --specs` and the active
change under `openspec/changes/`.

## License

[MIT](LICENSE) © Tarkov Companion contributors.
