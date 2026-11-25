# Kanban tag taxonomy

The board keeps its five columns. Work type is expressed with tags so planning and implementation cards
can coexist without adding columns.

## Two axes

Every card gets **exactly one type tag**:

| Tag | Use for |
|---|---|
| `planning` | Discovery, decisions, reviews, spikes, legal/infra setup — work that produces a decision or artifact, not shipped code |
| `implementation` | Code, tests, fixtures, CI, packaging — work that changes the repository's behavior |

Optionally add **area tags** (one or two):

| Tag | Area |
|---|---|
| `data` | Upstream contract, pipeline, bundles, fixtures, game data |
| `app` | Flutter client, navigation, local database, export/import |
| `infra` | GitHub Actions, releases, signing, repository settings |
| `design` | UI/UX exploration and the eventual design system |
| `legal` | Licensing, attribution, trademark |

Planning cards also keep their activity tags: `decision` for a choice that must be recorded, `spike` for a
time-boxed investigation.

## Rules

- A card must never have both `planning` and `implementation`.
- An implementation card that is in progress should carry the linked `sessionID` so the board opens the
  session that is doing the work.
- Card titles for implementation work use the OpenSpec task id (`T2.2 — …`) so the board and
  `openspec/changes/bootstrap-tarkov-companion/tasks.md` stay in sync.
- A card moves to Done only when the task's own verification passes and, for implementation, the commit is
  pushed.

## Filtering

- All implementation work: filter by `implementation`.
- All pipeline work: `implementation` + `data`.
- All open decisions: `planning` + `decision`.
- Release readiness: `implementation` + `infra`.
