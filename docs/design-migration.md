# Items design-system migration (T8.13)

T8.12 delivered the phosphor tokens, theme and primitives. T8.13 installs that
theme in the running app and migrates the Items experience: the catalog and the
item detail screen. Quests remain on the old Material styling until T8.14.

Reference visuals: [`design/preview/05-items-night-vision.png`](../design/preview/05-items-night-vision.png)
(1440), [`design/preview/06-items-1920-nv.png`](../design/preview/06-items-1920-nv.png)
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

```bash
cd app
flutter test packages/features/test/catalog
flutter test packages/features/test/catalog --update-goldens
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
- **Quest screens.** The list, trader strip and quest detail still need the
  T8.14 migration. They inherit the installed theme, but their layout, row
  density and state controls are untouched.
- **Trader offers, buy limit and price sparkline.** The design shows these in
  the inspector; the data and queries for them are outside this task.
- **True 24 h change.** See the column note above.
- **Item art.** Placeholder tiles stay until licensing/branding is decided.
