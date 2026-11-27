# Project handoff

Snapshot: **2026-11-26**. This is the resume point for working from another machine.

## Where the project is

- Repository: <https://github.com/Tayuha/tarkov-companion> — **public**, MIT.
- Default branch: `main`, everything pushed.
- Data plane is live: `data-regular-latest`, `data-pve-latest`, `data-pvp-season-latest`, refreshed by
  `.github/workflows/data-sync.yml` every 6 hours.
- Platform decision: **Linux desktop is the first release target**. Windows and mobile stay buildable and
  CI-checked, but packaging is deferred until the Linux build is approved.
- The first Linux AppImage was built and launched successfully; catalog, item detail, navigation shell,
  quest list and quest detail are implemented. The manual approval of the quest flow was the last pending
  check.

## What works

- First-run sync: manifest → compatibility → download → SHA-256 verify → transactional ingest, with
  progress, cancel, resume and retry.
- Catalog: search, category/type/flea filters, sorting, pagination, item detail with type-specific stats,
  prices and links.
- Quests: list with filters and state badges; detail with objectives, counters, requirements/lock reasons,
  rewards/turn-in items, unlocks, wiki; state changes and manual override.
- Navigation shell: Items/Quests rail (bottom bar under 700 px), state preservation.
- Packaging: `scripts/package-linux.sh` produces an AppImage, optional `.deb`, and `SHA256SUMS`;
  `package-linux` CI job uploads them.
- Data + unit tests: 388 data-package, 52 features, 24 app, 3 core (benchmark included in the data count
  when not excluded).

## Known gaps / next tasks

Read the Kanban board (`kanban-board.json`) and `openspec/changes/bootstrap-tarkov-companion/tasks.md`.
The immediate queue:

1. **T8.9** — manual Linux approval: checksums → launch → sync → catalog → item detail → quests →
   quest status/objectives → offline restart. Packaging is in **Review**.
2. **T6.9** available-quests view, **T6.8** orphaned-progress UI, **T6.10** game-mode scoping,
   **T6.11** quest docs.
3. **T5.4** acquisition/disposition sections, **T5.5** price presentation, **T5.6** image cache,
   **T5.7** price history, **T5.8** deep links, **T5.9** catalog performance, **T5.10** real category
   labels.
4. **T6.12** real trader/map labels for quest filters.
5. **T7.2–T7.10** profile level, reset/deletion, export/import.
6. **T8.2–T8.10** startup, update controls, offline/error states, window geometry, single instance,
   keyboard, about, Linux package/checksums.
7. **T9.x** end-to-end, offline checklist, recovery, network audit, release.

Windows and mobile packaging resume only after T8.9 is approved.

## Build and run on the home desktop

Repository on the home desktop: **`/home/tayuha/Projects/tarkov-companion`** (user `tayuha`). The SDK lives
at `~/.local/flutter`; the interactive shell is fish and already has it on `PATH`.

Prerequisites: Flutter **3.50.1**, Dart 3.14, Node **24**, `ninja`, clang/cmake/GTK3.

```bash
git clone https://github.com/Tayuha/tarkov-companion.git
cd tarkov-companion

# Pipeline
cd pipeline && npm ci && npm run lint && npm test && npm run build && cd ..

# App
cd app
flutter pub get
flutter analyze
flutter test
flutter run -d linux
```

Package the Linux app:

```bash
cd /path/to/tarkov-companion
bash scripts/package-linux.sh
# dist/TarkovCompanion-<version>-x86_64.AppImage
# dist/SHA256SUMS
```

The release used for the first approval attempt was
`TarkovCompanion-0.1.0-x86_64.AppImage`, SHA-256
`dd4e576bd5d9dc6e78ee9886860f1a6135bae76922d41e788720579b3fd2ede4`. Rebuild it after pulling; `dist/` is
not tracked.

Data directory on Linux: `~/.local/share/tarkov_companion/{db,logs,downloads}`.

## Resume this conversation

The latest full session export is the git-ignored **`homework/conversation.json`** (≈4 MB, mode 600, local
service password redacted). It contains local paths and tool output; keep it private and do not commit it.

On the home desktop:

```bash
cd /home/tayuha/Projects/tarkov-companion

opencode session import homework/conversation.json --directory "$PWD"
opencode session list

# The original id is preserved by the export:
opencode -s ses_dec935cb8ffez3EAaDtvaYTOzo
```

If the desktop keeps sessions under a different project, `--directory` attaches the import to the clone;
use the id printed by `session list` if it differs. The child subagent sessions are not needed — their
reports are in the parent transcript.

## Useful commands

```bash
openspec list --specs
openspec show bootstrap-tarkov-companion
openspec validate bootstrap-tarkov-companion --strict

# Optional local watchdog (Linux, desktop notifications)
python3 scripts/dev/subagent_watchdog.py --dry-run
```

The watchdog automation itself lives in the local OpenCode instance, not in the repository.
