# Design-system migration (T8.13–T8.14)

T8.12 delivered the phosphor tokens, theme and primitives. T8.13 installed that
theme in the running app and migrated the Items experience: the catalog and the
item detail screen. T8.14 migrated the Quests experience: the quest list and the
quest detail screen. Both features now share one visual vocabulary and no
feature screen writes a colour literal.

Reference visuals: Items at
[`design/preview/05-items-night-vision.png`](../design/preview/05-items-night-vision.png)
(1440) and [`design/preview/06-items-1920-nv.png`](../design/preview/06-items-1920-nv.png)
(1920); Quests at [`design/preview/02-quests.png`](../design/preview/02-quests.png)
(1440) and [`design/preview/07-quests-1920-nv.png`](../design/preview/07-quests-1920-nv.png)
(1920). The token and primitive contract is in
[`design-system.md`](design-system.md).

## Theme installation

`app/lib/main.dart` now builds the whole app with `buildAppTheme()`:

```dart
MaterialApp(
  theme: buildAppTheme(),
  darkTheme: buildAppTheme(),
  themeMode: ThemeMode.dark,
  ...
)
```

The default `ColorScheme.fromSeed(deepPurple)` is gone. Every route, including
the app bar, navigation rail, dialogs, inputs, progress indicators and pushed
detail pages, inherits the phosphor `ColorScheme` and `AppTokens` extension.
`app/test/widget_test.dart` asserts that the installed theme is dark, carries
`AppTokens`, uses the phosphor background/accent and the Fira UI family.

## Catalog

`CatalogScreen` keeps its presentation state, repository calls, debounce,
filters, sorting, pagination, empty/error states and the
`onItemSelected`-then-`ItemDetailScreen` navigation contract. Only the
presentation changed.

- Search, sort field/direction and filters use the themed `TextField`, a framed
  mono dropdown and `AppChip`/`AppButton` instead of stock Material controls.
- The result heading is a mono `CATALOG` label, an `h1` title and the data-style
  count.
- Active filter chips keep their sentence-case labels and close affordance, but
  use the accent-deep pill from the design system.
- Rows are built by `CatalogTableRow` (desktop) or `CatalogItemRow` (compact).
  Both are image-free and keep the neutral 40 px placeholder.
- Desktop rows are 72 px and alternate between `surface` and `background`.
  Flea price uses `value`, the base price is a dim mono subline, positive change
  is `success`, negative change is `danger` and unknown values are an em dash in
  `muted`.
- A 34 px header (`CatalogTableHeader`) labels the real columns.

### Responsive columns and width cap

`CatalogScreen` measures the available width inside a `ConstrainedBox` and picks
a `CatalogLayout`:

| Content width | Layout | Columns |
|---|---|---|
| `< 1100` | `compact` | No header; card rows with placeholder, name/meta, flea price and change. |
| `1100–1599` | `standard` | Item, Flea + Base subline, 24H, Weight, Slots. |
| `≥ 1600` | `wide` | Standard plus `Observed` (age of `priceObservedAt`) and a wider item cell. |

The content is capped at `CatalogScreen.maxContentWidth` = 1600 logical pixels
and centred, so a 2560 px monitor does not stretch the table into unreadable
columns. At 1920 the cap leaves the table at 1600 px; at 1440 it fills the
window.

The `24H` header follows the approved design. The only percentage available on
`ItemSummary` is `change48hPercent` (`changeLast48hPercent` in storage), so that
value backs the column. Exposing a true 24 h delta belongs to the data layer,
not this migration.

## Item detail

`ItemDetailScreen` keeps the strict omission rule and the typed-section switch.
Rows are still emitted only when the typed property exists, so a weapon never
shows damage, ammunition never shows ergonomics and a barter-only item has no
type-specific panel.

- Header: `surfaceRaised` placeholder tile with a 2 px corner, mono item-id
  label, `h1` name, mono short name and bordered sentence-case tags.
- Base facts use `AppStatTile` cells inside an `AppPanel` labelled `PROPERTIES`.
- Typed sections, categories, links and description are `AppPanel`s with
  `AppSectionLabel` headings.
- Links render as `info`-coloured selectable text; all actions are `AppButton`s.
- The content is capped at 1180 px. From 1080 px the layout is two columns:
  properties/typed/description on the left, categories/links on the right.
  Below that the original ordered single column is kept.

## Quests

`QuestListScreen` keeps its query state, debounce, filters, pagination,
empty/error states and the `onQuestSelected`-then-`QuestDetailScreen`
navigation contract. Presentation only changed.

- The search field, trader/map/level dropdowns and reset action use the themed
  input, framed mono dropdown and `AppButton` from the design system.
- State is a row of `AppChip` segments (`All states`, `Not started`,
  `In progress`, `Completed`, `Failed`). Active filters are removable
  `AppChip` tokens with the same accent-deep fill.
- The heading is a mono `QUESTS` label, an `h1` title and the data-style count.
- Status badges use `AppStatusBadge`. With a profile, the derived availability
  supplies `available`, `inProgress`, `completed` and `locked`; a failed quest
  keeps `failed` even though its availability is locked. Without a profile the
  recorded state is shown, with `notStarted` rendered as `Not started`. Colour
  is never the only carrier: every badge carries its word.
- Progress is the required-objective fraction (`satisfied / required`).
  Optional objectives never enter the denominator. A quest with no countable
  objectives shows an em dash.
- Desktop rows are 72 px and alternate `surface`/`background`, matching the
  catalog density. Compact rows keep the old card shape and a 24 px badge.

### Responsive columns and width cap

`QuestListScreen` measures the available width inside a `ConstrainedBox` and
picks a `QuestLayout`:

| Content width | Layout | Columns |
|---|---|---|
| `< 1100` | `compact` | No header; card rows with name/meta, status and progress. |
| `1100–1599` | `standard` | Quest, Trader, Map, Status, Progress. |
| `≥ 1600` | `wide` | Standard plus `Level` and a wider quest cell. |

The content is capped at `QuestListScreen.maxContentWidth` = 1600 logical pixels
and centred. At 1920 the table stays 1600 px wide; at 1440 it fills the window.

`QuestDetailScreen` keeps the strict omission rule and the typed/conditional
sections:

- Header: mono `QUEST DETAIL` label, `h1` name, recorded-state and availability
  badges, bordered metadata tags, mono wiki link.
- Objectives are `AppPanel` cards with a checkbox, the description and meta,
  the count controls and an `AppProgressBar`; the panel trailing readout is the
  required-objective fraction.
- Requirements, rewards, unlocks and status are `AppPanel`s. Reward items,
  standing, skills, offers and crafts are `AppStatTile` tiles.
- Actions are `AppButton`s: secondary for in progress, primary for completed,
  danger for failed, ghost for revert.
- A quest without a description has no Notes panel, an empty reward block has
  no Rewards panel, and a quest with no unlocks has no Unlocks panel. Derived
  explanatory copy is not a placeholder for a missing field.
- The content is capped at 1180 px. From 1080 px it splits into two columns:
  objectives/required items/notes on the left; rewards/requirements/unlocks/
  status on the right. Below 1080 the same content is one ordered column.

## Tests and goldens

Catalog widget tests now install `buildAppTheme()` and cover:

- the 1440 five-column header (`ITEM`, `FLEA`, `24H`, `WEIGHT`, `SLOTS`);
- the 1920 `OBSERVED` column and a wider item cell;
- compact rows with no header below 1100;
- the 1600 px content cap at 2560;
- alternating row surfaces;
- the existing filter/reset, sort, pagination, empty-state and tap flows.

Item detail tests cover the two-column and single-column layouts in addition to
the existing structural omission, not-found and error tests. The four detail
goldens (weapon, ammunition, armor, barter) were regenerated with the phosphor
theme and the bundled fonts.

Quest list tests cover the 1440 five-column header (`QUEST`, `TRADER`, `MAP`,
`STATUS`, `PROGRESS`), the 1920 `LEVEL` column and wider quest cell, compact
rows below 1100, the 1600 px cap at 2560, filter/reset and state chips,
availability/failed badge mapping, required-objective fractions, pagination and
row taps. Quest detail tests cover two-column and single-column layouts, the
omission rule, objective progress rails, not-found/orphaned states and the
existing action callbacks. Four quest goldens (list at 1440 and 1920, detail at
1440 and 900) are generated with the phosphor theme and bundled fonts.

```bash
cd app
flutter test packages/features/test/catalog
flutter test packages/features/test/catalog --update-goldens
flutter test packages/features/test/quests
flutter test packages/features/test/quests --update-goldens
flutter test
dart test packages/core
dart test packages/data --exclude-tags benchmark
dart run tool/check_architecture.dart
flutter build linux --debug
```

## What remains

- **Split inspector.** The wide design pairs the table with a right-hand item
  inspector. T8.13 keeps navigation to `ItemDetailScreen`; adding an embedded
  inspector (and selection state that does not conflict with the pushed route)
  is a follow-up.
- **Quest chain graph and map panel.** The 1920 Quests concept adds a quest
  chain and a location panel under the objectives. They are concept-only: the
  data has no chain projection or map artwork, so T8.14 does not fake either.
- **Trader portrait strip.** The concept's left trader strip is not part of the
  list contract; trader names are the filter and row data.
- **Trader offers, buy limit and price sparkline.** The design shows these in
  the inspector; the data and queries for them are outside this task.
- **True 24 h change.** See the column note above.
- **Item art.** Placeholder tiles stay until licensing/branding is decided.
