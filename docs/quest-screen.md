# Quest catalog screen

`QuestListScreen` (`app/packages/features/lib/src/quests/`) is the browse-first
view of the quest tracker. It is presentation-only: every row, count and page
comes from `QuestRepository` in the data package, so the screen works entirely
against the local database with no network request.

The screen has two views behind one route: the **catalog** (search, filters,
pagination) and **Available** (quests the active profile can start now, with
its own ordering). The data layer still owns derivation and this screen only
renders the resulting `QuestStatus`; it does not explain locked reasons, open a
detail view, or write progress.

## Composition

| Widget | Responsibility |
| --- | --- |
| `QuestListScreen` | Owns the query state, view segment, debounce timer, pagination and loading/error state. |
| `QuestFilterBar` | Trader, map and level dropdowns, `AppChip` state segments and the active-filter tokens. |
| `_QuestViewSegment` | Switches between **Catalog** and **Available** without a route change. |
| `_AvailableToolbar` | Level / trader / map / name ordering for the available view. |
| `_UnavailableQuestsPanel` | Lists preserved progress for quests missing from the active dataset. |
| `QuestListRow` | The compact card row: name, trader/level/map meta, status badge and progress. |
| `QuestTableHeader` / `QuestTableRow` | The desktop table from 1100 px, with an extra level column from 1600. |
| `QuestStateBadge` / `QuestAvailabilityBadge` | `AppStatusBadge` wrappers for a recorded state and a derived availability. |

`QuestListScreen` takes its `QuestRepository`, an optional `profileId`, an
optional `onQuestSelected`, a `pageSize` (default 50), a `searchDebounce`
(default 300 ms), and optional trader/map option lists. It never pushes a route;
the app shell decides what a row tap means.

## Views

The **Catalog** / **Available** segment is shown only when a profile is active.
It stays on the same route, so the shell's navigation contract is unchanged.

The available view calls `QuestRepository.availableQuests(profileId, sort:)`
and renders only `available` statuses. It hides search and the catalog filters,
because "what can I start now" is its whole question, and offers four ordering
criteria: **Level** (default), **Trader**, **Map** and **Name**. The result
count reads `N available quests`. Rows reuse the same table and compact card, so
the status badge is `AVAILABLE` and the progress fraction is still the required
objective fraction.

With nothing available, the view renders an explanatory empty state:
"Nothing is available to start." plus the reason that every remaining quest is
locked by a level, trader, or prerequisite requirement, in progress, or
completed, with a button back to the catalog. The state is not a generic "no
results": it names the possibilities and keeps lock reasons one tap away.

The catalog header count remains `Showing X of Y quests`; the available view
uses its own count and does not paginate.

## Unavailable upstream panel

When `QuestRepository.orphanedProgress` returns rows, a panel above the table
lists each quest id, its preserved recorded state and how many objective counts
survive. The panel states that the quests are missing from the active dataset
and excluded from requirement calculations. It never removes the catalog or
turns a missing quest into a fake row; the detail screen has the matching
"Quest unavailable upstream" state.

A quest that exists in another game mode is not listed here: it is excluded
from this profile's catalog by mode scoping and returns when that mode's
profile is active.

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

`profileId` scopes the progress read and the game mode. With `null` there is no
profile, so every quest reads as not started and the catalog is unscoped. Two
profiles render independent badges; switching the active profile in the app
shell and passing its id is enough to change every badge and the visible task
set. A task whose bundle `gameMode` list does not contain the profile's mode is
absent from the catalog and the available view (a PvE-only quest does not appear
under a regular profile).

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

## Offline and upstream states (task 8.4)

`QuestListScreen` accepts an optional `UpstreamCheck`, the same presentation
seam the catalog uses. It runs beside the local query and never gates rows.

* **Saved quests plus a failed check** — every row stays; an `AppStatusStrip`
  above the table names the saved data and offers **Retry**.
* **Retry in flight** — the strip switches to `CHECKING FOR UPDATES` and the
  segment, filters, pagination and badges stay usable.
* **Empty catalog plus a failed check** — an explicit **No quests are saved
  yet** state with the local-first explanation and **Retry update**, not the
  generic empty or error screen.
* **Available segment** — the derived list is local, so a failed check keeps
  it. Its empty result has an offline variant that says availability is still
  computed from saved progress and offers both **Retry update** and **Open
  catalog**.
* **Detail route** — `QuestDetailScreen` accepts the same check and shows a
  non-blocking strip above the saved detail. A repository error that is an
  upstream/sync failure renders the offline strip with retry instead of the
  generic error; a corrupt local record keeps the generic error.

## Tests

`app/packages/features/test/quests/quest_list_screen_test.dart` runs against an
in-memory `AppDatabase` seeded with two profiles, fifteen quests (fourteen
shared plus one PvE-only), objective counts and their recorded progress, through
the real `QuestRepository`. It covers the initial load and metadata, debounce
timing, diacritic search, every filter alone, a combined filter, reset,
per-profile badge isolation, the availability/failed badge mapping, the
objective fraction, the 1440 and 1920 table columns, the compact fallback, the
1600 px cap, the empty state with the preserved query and reset, pagination with
load-more, row-tap reporting, game-mode scoping, the populated available view
with ordering, the explanatory available empty state, the unavailable-upstream
panel, and list goldens at 1440 and 1920. No test performs network access.

`quest_offline_test.dart` covers the network states with a failing closure:
populated cache plus offline, retry re-running the check, the available segment
through an outage, the empty-catalog offline state, and the available segment's
offline empty explanation.
