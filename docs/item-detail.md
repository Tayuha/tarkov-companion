# Item detail view

The item detail view is the read-only page for one catalog item. Every fact it
shows comes from the local database or the bounded image/history caches; the
screen itself never fetches a catalog document.

## Data API

`CatalogRepository.itemDetail(id)` returns an `ItemDetail` or `null` when the
current dataset has no item with that id. It reads:

- the indexed `items` columns (`name`, `shortName`, `weight`, `width`,
  `height`);
- the canonical `payload` JSON for everything else (`description`,
  `basePrice`, `price`, `iconLink`, links, conflicts, type-specific
  `properties`);
- the `itemTypes` and `itemCategories` join rows;
- the display names of categories from the `gameRecords` records of kind
  `itemCategory` and `handbookCategory`, falling back to the category id when a
  name is absent.

The payload is parsed once into a typed `ItemProperties` subclass:

| `propertiesType` / item type | Model | Fields |
|---|---|---|
| `ItemPropertiesWeapon` / `gun` | `WeaponProperties` | caliber, fire rate, ergonomics, vertical and horizontal recoil, effective range, fire modes, attachment slots |
| `ItemPropertiesAmmo` | `AmmunitionProperties` | caliber, damage, penetration power, armor damage |
| `ItemPropertiesArmor`/`Helmet`, `armor`/`helmet` | `ArmorProperties` | class, durability, protected zones, material |
| `ItemPropertiesMedKit`/`Stim`/`MedicalItem`/`Painkiller`/`SurgicalKit`, `meds`/`injectors` | `MedicalProperties` | uses, hit points, hit points per use, use time, cures, stim effects |
| anything else | `GenericProperties` | no type-specific fields |

A corrupt payload throws a `FormatException`; the screen shows its error state
instead of inventing values. An unknown id returns `null`, which the screen
renders as the not-found state.

`CatalogRepository.itemRelations(id)` returns the acquisition/disposition
record described below, or `null` for an unknown id.
`CatalogRepository.categoryOptions()` returns the id/name pairs the catalog
filter uses; it is the same bundle category vocabulary the header renders.

## Sections

1. **Header** — item image (or neutral placeholder), name, short name, and type
   chips.
2. **Properties** — weight, grid size, and stack limit when the bundle has
   them.
3. **Prices** — flea low, 24 h average, 48 h direction, trader base price and
   observation time; explicit missing and zero states.
4. **Categories** — item and handbook category labels, when the item has any.
5. **Links** — the wiki URL and the tarkov.dev page as selectable text. The
   app does not open an external browser yet.
6. **Acquisition** — trader buy offers, barters offering the item, crafts
   producing it, and quests that require it or unlock an offer.
7. **Disposition** — trader sell offers, plus barters and crafts that consume
   the item as an input.
8. **Price history** — the on-demand cached chart, when a history repository is
   supplied.
9. **Type-specific section** — exactly one of *Weapon*, *Ammunition*, *Armor*
   or *Medical*, depending on the typed property set. A weapon adds its
   compatible slots with required/optional markers.
10. **Description** — the localized description, when present.

## Omission rule

A property is rendered only when it applies to the item's kind **and** has a
value. The rule has two layers:

- **Type layer.** The property groups are disjoint classes, so a weapon has no
  `damage` field to render and ammunition has no `ergonomics` field. A section
  whose item kind does not match is never created.
- **Value layer.** Every row is added only when its parsed value is non-null and
  non-empty (positive numbers, non-empty strings and lists). No row is ever
  rendered as zero or "N/A", and a typed section with no rows is omitted
  entirely.

A barter-only item (for example the Leatherman Multitool) therefore shows the
header, base properties, categories, links, and description — and no
type-specific, price, acquisition, disposition or history section.

Zero is treated as "no value" for the type-specific numeric fields because the
bundle uses absent fields for "not applicable". A zero **price** is the
exception: it is a real observation and is labelled instead of omitted (see
below).

## Acquisition and disposition (task 5.4)

`ItemRelationsRepository` builds `ItemRelations` from the tables ingestion
already fills:

* **Trader buy/sell** — the item payload's `buyFromTrader` (trader sells to the
  player) and `sellToTrader` (trader buys from the player). Trader display names
  come from `traders`; a missing trader falls back to its id. A buy offer's
  `taskUnlockId` is resolved to the task name when `tasks` has it.
* **Barter** — rows in `barters` whose `offeredItem` is this item are
  acquisition; rows whose `requiredItems` contain it are disposition ("used
  for"). Item names are resolved from `items`, with the id as fallback.
* **Craft** — rows in `crafts` whose `productItemId` is this item are
  acquisition; rows whose `requiredItems` contain it are disposition. The
  station name comes from `hideoutStations`.
* **Quest requirements** — `taskObjectives` whose payload's `itemIds` contain
  the item, one row per objective; plus any `taskUnlockId` on a trader offer.

The nested arrays are queried with SQLite JSON1 (`json_each`) over the
canonical payload, so no relationship is duplicated into a client-only table.
All queries are local reads; the section needs no network. A relationship whose
dataset has not been applied is absent, not invented.

`app/packages/data/test/catalog/item_relations_test.dart` ingests the committed
normalized `items`, `traders`, `hideout`, `barters`, `crafts` and `tasks`
fixtures; the widget tests seed the same relationships by hand.

## Prices (task 5.5)

The `Prices` panel labels each source explicitly:

| Row | Field | Notes |
|---|---|---|
| `Flea · low` | `price.lastLow` | Latest flea low. `0` renders the explicit zero state, `No flea offers (0 ₽)`. |
| `Flea · 24 h avg` | `price.avg24h` | Hidden when the bundle has no positive average. |
| `Flea · 48 h` | `price.change48hPercent` + `price.change48h` | `Rising`/`Falling`/`Flat`, signed percent and absolute change. |
| `Trader · base` | `basePrice` | The trader-independent base value. |
| `Observed` | `price.observedAt` | Absolute UTC timestamp. |

When neither flea field is present the panel names the state instead of showing
a price: `No flea price observed yet.` for an eligible item, or `Not available
on the flea market.` for an item with the `noFlea` type. The 24-hour average is
the bundle's `avg24h`; the only change percentage the pipeline publishes is
48-hour, so the detail panel never labels it as a 24-hour change. The catalog
table keeps its historical `24h` column heading for that same field; see
[`catalog-screen.md`](catalog-screen.md).

## Images (task 5.6)

`ItemImageCache` (`app/packages/features/lib/src/catalog/item_image.dart`) is a
disk-backed LRU cache:

* lazy — bytes are requested only when an `ItemImage` is built for a visible
  row or the detail header;
* disk-backed — files are named by a stable FNV-1a hash of the URL, so an
  offline run hits the same file;
* bounded — after each write, least-recently-used files are evicted until the
  directory is at or below `maxBytes` (default 32 MiB); reads touch the file's
  modification time, and an image larger than the whole budget is served but
  not retained;
* failure-safe — a malformed URL, failed fetch or I/O error returns `null` and
  the neutral placeholder is rendered without changing layout.

Network fetches go through `AllowlistedItemImageFetcher`, which wraps
`AllowlistedHttpClient`; the only reachable image host is the documented
`assets.tarkov.dev` allowlist entry. Tests inject a fake fetcher and never open
a socket.

`ItemDetailScreen` and `CatalogScreen` accept an optional `imageCache`. The
production session builds one cache over `<data>/cache/images` with the
allowlisted fetcher and shares it through the shell with the catalog and every
detail route. Sessions without a cache (shell tests) keep the placeholder and
perform no I/O.

## Price history (task 5.7)

The published bundle has **no history dataset** — only the current `price`
snapshot. `PriceHistoryRepository` therefore keeps the network behind the
`PriceHistorySource` interface:

* `load` serves a cache whose newest observation is inside the TTL (default
  6 h) without calling the source;
* an expired cache is refetched online and replaced atomically;
* `offline: true` never calls the source: it returns the cache, or the
  `unavailable` snapshot that `PriceHistoryChart` renders as "Price history
  unavailable offline";
* a failed refresh falls back to a stale cache and marks the chart stale, and
  with no cache it is unavailable — no point is ever fabricated.

The unavailable and stale chart states use the shared `AppStatusStrip`
(offline and stale intents), so their wording matches the catalog and quest
status strips. When the screen supplies a callback, the strip offers the same
**Retry** action and reloads only the history, leaving the item detail visible.

The cache lives in the existing `priceHistory` table (`itemId`, `observedAt`,
`price`, `priceMin`). Because that table has no fetch timestamp and a schema
change was not justified for a cache, the TTL is measured from the newest
stored observation; see [`freshness.md`](freshness.md).

There is no production `PriceHistorySource` until a documented history endpoint
is added to `NetworkAllowlist`. The app omits the section when no repository is
supplied, and the tests use a fake source. The chart itself is
`PriceHistoryChart` in `app/packages/features/lib/src/catalog/`.

## Layout

The inspector caps content at 1180 logical pixels. From 1080 pixels the
base/price/typed facts and the categories/links/acquisition/disposition/history
panels split into two columns; narrower windows keep one ordered column, with
categories and links following the properties.

`ItemDetailScreen` also accepts an optional `UpstreamCheck`. Saved item content
stays visible under a non-blocking `AppStatusStrip` when the check fails; a
repository error classified as an upstream/sync failure renders the offline
strip with retry, while a corrupt payload keeps the generic error state.

## Tests

`app/packages/features/test/catalog/item_detail_screen_test.dart` renders a
weapon, ammunition, armor, and a barter-only item as golden images under
`goldens/` (960 × 1500, the phosphor theme and bundled fonts, device pixel
ratio 1). It also asserts the omission rule structurally: a weapon has no
ammunition rows, an ammunition item has no weapon rows, a barter-only item has
no typed section, and a medkit without `uses` does not show a Uses row. New
tests cover the complete, missing-flea and zero-price states; acquisition and
disposition rows from fixture relationships; the all-missing case; the header
image cache; the online history chart; and the offline-without-cache state. The
single-column and wide two-column layouts are covered, as are loading,
not-found with back navigation, and corrupt-payload error states. The
network-state tests add a saved item with a failing upstream and the history
strip's retry action.

`app/packages/data/test/catalog/item_detail_test.dart` checks the parser against
the committed normalized item fixture, including prices, a missing id and a
corrupt payload. `item_relations_test.dart`, `price_history_test.dart` and
`category_options_test.dart` cover the related data contracts.

## Out of scope

Deep-link routing by game id (task 5.8) is separate. The image cache is wired
by the production session. The price-history source stays injectable but
unwired because the published bundle has no history endpoint; the screen
renders the documented unavailable state instead.
