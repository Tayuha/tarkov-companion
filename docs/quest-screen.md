# Quest catalog screen

`QuestListScreen` (`app/packages/features/lib/src/quests/`) is the browse-first
view of the quest tracker. It is presentation-only: every row, count and page
comes from `QuestRepository` in the data package, so the screen works entirely
against the local database with no network request.

This is the **catalog list** only. The data layer still owns derivation
(task 6.3) and this screen only renders the resulting `QuestStatus`; it does not
explain locked reasons (6.4), open a detail view (6.5), or write progress (6.6).

## Composition

| Widget | Responsibility |
| --- | --- |
| `QuestListScreen` | Owns the query state, debounce timer, pagination and loading/error state. |
| `QuestFilterBar` | Trader, map and level dropdowns, `AppChip` state segments and the active-filter tokens. |
| `QuestListRow` | The compact card row: name, trader/level/map meta, status badge and progress. |
| `QuestTableHeader` / `QuestTableRow` | The desktop table from 1100 px, with an extra level column from 1600. |
| `QuestStateBadge` / `QuestAvailabilityBadge` | `AppStatusBadge` wrappers for a recorded state and a derived availability. |

`QuestListScreen` takes its `QuestRepository`, an optional `profileId`, an
optional `onQuestSelected`, a `pageSize` (default 50), a `searchDebounce`
(default 300 ms), and optional trader/map option lists. It never pushes a route;
the app shell decides what a row tap means.

## Search and debounce

* Typing waits for 300 ms of idle input before the text reaches the repository.
  Pressing Enter applies the text immediately.
* Search matches quest names case- and diacritic-insensitively, token by token,
  using the data layer's folded search key. `cafe` matches `Café Crème`;
  `punisher` matches both `The Punisher - Part 1` and `- Part 2`.
* A request that fails while rows are already visible keeps those rows and shows
  a retry banner; loading a new query keeps the previous rows under a progress
  bar instead of blanking the screen.
* Every repository request increments a generation counter. A response whose
  generation is no longer current is dropped without touching state, so a slow
  request for an older query cannot overwrite a newer one.
* Clearing the search (the field's clear button, the active `Search:` chip or
  the reset action) cancels a pending debounce.

## Filters

* **Trader** and **map** dropdowns come from caller-supplied
  `QuestFilterOption` lists. The quest dataset stores upstream identifiers
  only; localized display names come from the caller (or fall back to the id).
  This mirrors `CatalogCategoryOption` in the item catalog.
* **Level** is an inclusive upper bound: `Level ≤ 15` keeps quests whose
  required minimum level is at or below 15. Quests with an unknown required
  level are excluded because their gate cannot be proven. The list offers
  spaced bounds so the menu stays keyboard-navigable.
* **State** filters the profile's recorded progress: not started, in progress,
  completed or failed. It is a row of single-select `AppChip` segments; the
  filter still reaches the repository as `QuestFilters.state`, so it does not
  add a derived "available" filter.
* Filters combine with **AND**, with each other and with the search text.
* Every active filter appears as a removable `AppChip` token. Removing a token
  changes only that filter. The `Reset` action clears every filter and the
  search field.
* Changing any filter resets pagination to offset 0.

## Progress state and badges

`profileId` scopes the progress read. With `null` there is no profile, so every
quest reads as not started. Two profiles render independent badges over the same
quest catalog; switching the active profile in the app shell and passing its id
is enough to change every badge.

When the profile exists the screen also reads `QuestRepository.statuses` once
per reload. That gives each row its derived availability and a required-
objective fraction without a query per row:

| Shown state | Source | `AppStatusBadge` |
| --- | --- | --- |
| Available | derived availability | `available` (success) |
| Locked | derived availability | `locked` (dim) |
| In progress | derived availability | `inProgress` (info) |
| Completed | derived availability | `completed` (accent) |
| Failed | recorded state | `failed` (danger) |
| Not started | recorded state, no profile | `locked`, labelled `Not started` |

The failed override exists because a non-restartable failed quest derives as
locked; the list keeps the more specific failed word and colour. The progress
readout is `satisfied required objectives / required objectives`; optional
objectives are tracked but never enter the denominator.

## Responsive layout

| Content width | Layout |
| --- | --- |
| `< 1100` | Compact card rows, no header. |
| `1100–1599` | Table: Quest, Trader, Map, Status, Progress. |
| `≥ 1600` | Adds Level and widens the quest cell. |

The content is capped at `QuestListScreen.maxContentWidth` (1600 logical pixels)
and centred. Desktop rows are 72 px and alternate `surface`/`background`;
compact rows keep the touch-sized card shape.

## Pagination and virtualization

Rows live in a `ListView.builder`, so only the visible window is built. The
first page is `pageSize` rows; when more rows match, a footer shows
"`loaded` of `total` loaded" and a **Load more** button. Loading a page appends
to the existing list and updates the total count shown in the header. The screen
uses explicit load-more rather than scroll-triggered loading so the interaction
is deterministic and a keyboard user reaches it by tabbing.

## Empty, loading and error states

* **Empty** — the header shows `Showing 0 of 0 quests` and the body repeats the
  active query (for example `No quests match "zzzz".`) with a **Reset filters**
  button. A purely structured empty result names the active filters instead.
* **Loading** — the first load shows a centered spinner plus
  `Loading quests…`; a later query keeps the old rows and adds a
  `LinearProgressIndicator`.
* **Error** — a retry banner appears above the list; rows already loaded stay
  visible, and an initial failure leaves the banner with a retry action while
  the header keeps the catalog context.

## Tests

`app/packages/features/test/quests/quest_list_screen_test.dart` runs against an
in-memory `AppDatabase` seeded with two profiles, fourteen quests, objective
counts and their recorded progress, through the real `QuestRepository`. It
covers the initial load and metadata, debounce timing, diacritic search, every
filter alone, a combined filter, reset, per-profile badge isolation, the
availability/failed badge mapping, the objective fraction, the 1440 and 1920
table columns, the compact fallback, the 1600 px cap, the empty state with the
preserved query and reset, pagination with load-more, row-tap reporting, and
list goldens at 1440 and 1920. No test performs network access.
