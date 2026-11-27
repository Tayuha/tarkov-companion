# Item catalog screen

`CatalogScreen` (`app/packages/features/lib/src/catalog/`) is the browse-first
entry point into the item catalog. It is presentation-only: every list, count
and page comes from `CatalogRepository` in the data package, so the screen
works entirely against the local database with no network request.

## Composition

The screen is built from three small widgets:

| Widget | Responsibility |
| --- | --- |
| `CatalogScreen` | Owns the query state, debounce timer, pagination and loading/error state. |
| `CatalogFilterBar` | Category, type and flea controls plus the active-filter chips. |
| `CatalogTableHeader` / `CatalogTableRow` | The 1100 px+ table header and fixed 72 px data rows. |
| `CatalogItemRow` | The compact card row used below 1100 px. |

`CatalogScreen` takes its `CatalogRepository`, a `pageSize` (default 50), a
`searchDebounce` (default 300 ms), the category/type option lists, and an
optional `onItemSelected`. It never pushes a route; the app shell decides what a
row tap means.

## Search and debounce

* Typing waits for 300 ms of idle input before the text reaches the repository.
  Pressing Enter applies the text immediately.
* The text is combined with the other filters, so search and structured filters
  intersect.
* Every repository request increments a generation counter. A response whose
  generation is no longer current is dropped without touching state, so a slow
  request for an older query can never overwrite the results of a newer one.
* A request that fails while rows are already visible keeps those rows and shows
  a retry banner; loading a new query keeps the previous rows visible under a
  progress bar instead of blanking the screen.
* Clearing the search (the field's clear button, the active `Search:` chip or
  the reset action) cancels a pending debounce.

## Filters and sort

* Category filters use one category tree per option (`CatalogCategoryKind`).
  When the caller passes no options, the screen loads
  `CatalogRepository.categoryOptions()`, which returns the categories actually
  attached to items in the applied dataset with the display names from the
  bundle's `itemCategory`/`handbookCategory` records. A category without a
  record keeps its id. Callers may still pass explicit
  `CatalogCategoryOption`s to make a screen deterministic (the tests do).
* Type filters use the bundle `types[]` vocabulary (`gun`, `ammo`, `mods`, ...).
* Flea eligibility is a single toggle that filters to eligible items. The data
  layer also supports the opposite state; the chip can render either when the
  filter is set programmatically.
* Every active filter appears as a removable accent chip with its own remove
  action. Removing a chip changes only that filter. The `Reset` action clears
  every filter and the search field but keeps the chosen sort.
* Sort fields are name, base price, flea price and weight; the arrow button
  reverses the direction. The default order is the repository default:
  relevance while a search is active and name otherwise. Null prices/weights
  sort last in both directions, which is the repository's contract (an unknown
  price is not a zero price).

## Pagination and virtualization

Rows live in a `ListView.builder`, so only the visible window is built. The
first page is `pageSize` rows; when more rows match, a footer shows
"`loaded` of `total` loaded" and a **Load more** button. Loading a page appends
to the existing list and updates the total count shown in the header. A new
filter or sort resets pagination to offset 0. The screen uses explicit
load-more rather than scroll-triggered loading so the interaction is
deterministic and a keyboard user reaches it by tabbing.

## Empty, loading and error states

* **Empty** — the header shows `Showing 0 of 0 items` and the body repeats the
  active query (for example `No items match "zzzz".`) with a **Reset filters**
  button. A purely structured empty result names the active filters instead.
* **Loading** — the first load shows a centered spinner; a later query keeps the
  old rows and adds a `LinearProgressIndicator`.
* **Error** — a retry banner appears above the list; rows already loaded stay
  visible, and an initial failure leaves the banner with a retry action.

## Responsive layout

The screen measures the width available after the app shell and inside a
1600 px cap:

* **Below 1100 px** — compact card rows, no table header.
* **1100–1599 px** — five columns: Item, Flea + Base subline, 24H, Weight,
  Slots.
* **1600 px and wider** — the same columns plus `Observed`, the age of the
  newest price observation.

The 24H value is backed by `ItemSummary.change48hPercent`, the only change
percentage the data layer exposes today. The column heading is historical; the
item detail panel labels the same field `48 h` consistently. See
[`item-detail.md`](item-detail.md) and
[`design-migration.md`](design-migration.md).

## Images

`CatalogTableRow` and `CatalogItemRow` render the item's `iconLink` through
`ItemImage` when the screen is given an `ItemImageCache`. The cache is lazy,
disk-backed, bounded by an LRU byte budget and falls back to the same 40×40
neutral slot on a cache miss or fetch failure, so row height and the
virtualized list geometry never change. Without a cache (the app shell does not
pass one yet) the placeholder is used and no network or disk access happens.
See [`item-detail.md`](item-detail.md#images-task-56).

## Tests

`app/packages/features/test/catalog/catalog_screen_test.dart` runs against an
in-memory `AppDatabase` seeded through the FTS triggers and a real
`CatalogRepository`. It covers the initial load, debounce timing, each filter
chip applying and clearing, reset, the empty state with the preserved query,
sorting in both directions, pagination with load-more, row-tap reporting, the
1440/1920 column sets, compact fallback below 1100, the 1600 px cap and
alternating row surfaces.
