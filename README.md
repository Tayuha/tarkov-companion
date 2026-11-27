# Tarkov Companion

[![CI](https://github.com/Tayuha/tarkov-companion/actions/workflows/ci.yml/badge.svg)](https://github.com/Tayuha/tarkov-companion/actions/workflows/ci.yml)
[![Data sync](https://github.com/Tayuha/tarkov-companion/actions/workflows/data-sync.yml/badge.svg)](https://github.com/Tayuha/tarkov-companion/actions/workflows/data-sync.yml)

An open-source, local-first companion app for **Escape from Tarkov**: browse every item, follow the
flea market, and track quest progress — on your machine, offline, without an account.

> **Status: early Linux preview.** The data pipeline is live and the Linux client implements first-run
> sync, the item catalog and item detail, the quest list and interactive quest detail, profiles, and
> AppImage packaging. The Linux approval gate and the remaining backlog are tracked in
> [`HANDOFF.md`](HANDOFF.md) and `kanban-board.json`. Windows and mobile are deferred until the Linux
> build is approved. The public roadmap is [`docs/roadmap.md`](docs/roadmap.md).
>
> Visual concept: [`design/README.md`](design/README.md) — FigCraft pages, tokens and previews.

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
                                   Flutter app (Linux first; Windows/Android/iOS later)
                                       drift/SQLite = single read path
```

The app never calls the upstream API directly and never downloads a prebuilt database. A small
TypeScript pipeline validates and normalizes upstream JSON into versioned bundles; the app verifies each
dataset by SHA-256 and ingests it transactionally into its own schema. See
[`design.md`](openspec/changes/bootstrap-tarkov-companion/design.md) for the full rationale.

## Repository layout

| Path             | Purpose                                                                                      |
| ---------------- | -------------------------------------------------------------------------------------------- |
| `app/`           | Flutter client (Linux target at launch)                                                      |
| `pipeline/`      | Node/TypeScript data pipeline and bundle publisher                                           |
| `test/fixtures/` | Trimmed upstream fixtures used by tests                                                      |
| `docs/`          | Data bundle contract, sync protocol, local schema, progress format, release process, roadmap |
| `openspec/`      | Specifications, design, and implementation plan                                              |

## Building

Prerequisites: Flutter (stable), Node.js 24+ (the bundle writer uses built-in zstd), Git.

```bash
git clone git@github.com:Tayuha/tarkov-companion.git
cd tarkov-companion

cd pipeline && npm ci && npm test && npm run build
cd ../app && flutter pub get && flutter test && flutter run -d linux
```

The pipeline can run against committed fixtures without network access or secrets:

```bash
cd pipeline && npm run build -- --fixtures ../test/fixtures --out ../dist
```

Build the Linux release package (AppImage, optional `.deb`, and `SHA256SUMS`):

```bash
bash scripts/package-linux.sh
```

Artifacts land in `dist/`. See [`docs/linux-package.md`](docs/linux-package.md) for versioning,
checksum verification, and the manual approval checklist. The release workflow
(`.github/workflows/release-linux.yml`) runs on manual dispatch and on `v*` tags; a tag creates a
draft GitHub Release with the AppImage, optional `.deb`, `SHA256SUMS`, and generated notes that state
the unsigned status. Do not publish a release before the manual gate passes. See
[`docs/release.md`](docs/release.md).

Before opening a pull request, check formatting without rewriting unrelated files:

```bash
bash scripts/check-format.sh
```

The opt-in check covers `dart format` (80 columns) and Prettier for the release/CI docs. Existing
docs and pipeline sources have legacy formatting drift; `--all` reports it.

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
