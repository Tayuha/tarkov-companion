# Data bundles (draft)

> Draft for OpenSpec task 2.5. Task 2.10 finalizes the published contract
> (manifest fields, checksums, schema versions). This document defines the
> normalized record shape the bundle writer will serialize.

The pipeline turns each validated, localized upstream dataset into **JSONL**:
one JSON object per line, one record kind per line. The app ingests the records
into its own SQLite schema; it never interprets raw `json.tarkov.dev` payloads.

## File rules

- One dataset per file: `<mode>/<dataset>.jsonl` (`regular`, `pve`,
  `pvp-season`). Datasets: `items`, `tasks`, `traders`, `hideout`, `crafts`,
  `barters`, `maps`.
- Every line is a JSON object with a `kind` discriminator and a non-empty
  string `id`. `kind` + `id` is unique within a dataset.
- Records are sorted by `kind`, then `id`, using UTF-16 code-unit order.
- Object keys are sorted recursively (canonical key order). Array order is
  preserved because it is meaningful upstream.
- The file ends with a single trailing newline. The same validated input always
  produces byte-identical output.
- Text is English (`en`) only for now. Localization is resolved before
  normalization; a placeholder-shaped string is a normalization failure.
- Unknown upstream fields are dropped rather than passed through. The
  normalizer counts them per dataset (`droppedFields`, `droppedFieldPaths`) so
  a contract change is visible in the build log.

## Field conventions

| Concern | Convention |
|---|---|
| Field names | `camelCase`. |
| Identifiers | Non-empty strings. Upstream numeric ids are stringified. |
| References | End in `Id` / `Ids`: `traderId`, `traderIds`, `mapId`, `mapIds`, `itemId`, `itemIds`, `stationId`, `taskId`, `questItemId`, `keyItemId`, `achievementId`. |
| Related entities | Referenced by id only; the client joins locally. No entity objects are embedded. |
| Money | Integer number of roubles (`Math.round`). `currency` stays the upstream code (`RUB`, `USD`, ...). |
| Weight | Kilograms, as a number (upstream already serves kg). |
| Grid size | Integers (`width`, `height`). |
| Durations | Integer seconds (`raidDuration`, `constructionTime`, `craft.duration`). |
| Timestamps | ISO 8601 UTC strings ending in `Z`. Upstream epoch-millisecond strings are converted. |
| Objective types | `type` is always present. Only the fields admitted for that type are emitted; absent union fields are omitted, never `undefined`. |
| Opaque payloads | `map.btrStops` and `map.switches[].door` are copied as validated because upstream has no observable element shape. |

### Price object

Items carry the live price snapshot in `price`:

```json
"price": {
  "lastLow": 40000,
  "avg24h": 111351,
  "low24h": 28888,
  "high24h": 900000,
  "change48h": 16102,
  "change48hPercent": 16.91,
  "lastOfferCount": 36,
  "observedAt": "2026-11-25T17:08:02.000Z"
}
```

All money fields are roubles. `change48hPercent` is a percentage, not money.
Missing values are `null`, never omitted, so "no data" is explicit.
`observedAt` is the upstream `lastScan`. The root `lastScan`, `avg24hPrice`,
`changeLast48h`, `changeLast48hPercent`, `high24hPrice`, `lastLowPrice`,
`low24hPrice` and `lastOfferCount` fields are folded into `price` and are not
emitted again.

### Trader offers

Only the shape below is kept; upstream `currencyItem`, `restockAmount` and
`taskUnlock` on buy offers are dropped by contract.

```json
"buyFromTrader": [
  { "traderId": "5a7c2eca...", "price": 22997, "currency": "RUB",
    "loyaltyLevel": 3, "buyLimit": 5 }
],
"sellToTrader": [
  { "traderId": "54cb50c7...", "price": 18000, "currency": "RUB" }
]
```

`loyaltyLevel` is the upstream `minTraderLevel`. The key is only present when
upstream provides it.

## Intentional embedded values

- `task.finishRewards.customization[].name` is `"Unnamed customization"` when
  upstream has no dictionary entry for the name. This is the only place where
  normalization writes display text; the design requires a labelled fallback
  instead of publishing an unresolved key. The counter
  `stats.fallbacks.customizationName` reports how many were substituted.
- `craft.productItem`, `barter.offeredItem` and the various `requiredItems`
  entries keep `{ itemId, count, attributes }` rather than a bare id, because
  the count/attributes are part of the recipe, not of the referenced item.

## Record kinds

Counts below are the committed fixture output (2026-11-25), used by the golden
tests.

| Dataset | Kinds (count) | Records |
|---|---|---|
| `items` | `item` 60, `itemCategory` 142, `handbookCategory` 117, `fleaMarket` 1, `armorMaterial` 8, `playerLevel` 79, `mastering` 82, `skill` 49, `specialItem` 38, `setting` 1 | 577 |
| `tasks` | `task` 80, `questItem` 138, `achievement` 131, `prestige` 6 | 355 |
| `traders` | `trader` 16 | 16 |
| `hideout` | `hideoutStation` 26 | 26 |
| `crafts` | `craft` 20 | 20 |
| `barters` | `barter` 20 | 20 |
| `maps` | `map` 2, `mob` 2, `lootContainer` 43, `stationaryWeapon` 2, `goonReport` 1 | 50 |

Synthetic ids: `fleaMarket` and `setting` use `id` equal to the collection name;
`playerLevel` uses the level as a string; `specialItem` uses the item id;
`goonReport` uses `<mapId>@<observedAt>` (there can be more than one report per
map over time).

## Objectives

Common fields: `id`, `type`, `description`, `optional`, `mapIds`.

Type-specific fields (renamed references in parentheses):

| Type | Fields |
|---|---|
| `buildWeapon` | `buildAttributes`, `containsAllItemIds`, `containsCategoryIds`, `count`, `itemId`, `zones` |
| `dialogue` | `count`, `traderIds`, `zones` |
| `experience` | `bodyParts`, `count`, `effects`, `healthEffect`, `zones` |
| `extract` | `bodyParts`, `count`, `effects`, `exitName`, `exitStatus`, `healthEffect` |
| `findItem` | `count`, `dogTagLevel`, `foundInRaid`, `itemIds`, `maxDurability`, `minDurability`, `zones` |
| `findQuestItem` | `count`, `possibleLocations`, `questItemId`, `requiredKeyItemIds` |
| `giveItem` | `count`, `dogTagLevel`, `foundInRaid`, `itemIds`, `maxDurability`, `minDurability` |
| `giveQuestItem` | `count`, `questItemId` |
| `globalVariable` | `count`, `globalVariable`, `zones` |
| `haveItem` | `count`, `dogTagLevel`, `foundInRaid`, `itemIds`, `maxDurability`, `minDurability` |
| `hideoutStation` | `count`, `stationId`, `stationLevel` |
| `mark` | `count`, `markerItemId`, `requiredKeyItemIds`, `zones` |
| `plantItem` | `count`, `dogTagLevel`, `foundInRaid`, `itemIds`, `maxDurability`, `minDurability`, `requiredKeyItemIds`, `zones` |
| `plantQuestItem` | `count`, `questItemId`, `requiredKeyItemIds`, `zones` |
| `playerLevel` | `count`, `playerLevel` |
| `sellItem` | `count`, `dogTagLevel`, `foundInRaid`, `itemIds`, `maxDurability`, `minDurability`, `zones` |
| `shoot` | `bodyParts`, `count`, `distance`, `effects`, `enemyHealthEffect`, `healthEffect`, `notWearingItemIds`, `playerHealthEffect`, `shotType`, `targetNames`, `timeFromHour`, `timeUntilHour`, `usingWeaponItemIds`, `usingWeaponModItemIds`, `wearingItemIds`, `zones` |
| `skill` | `level`, `skill`, `zones` |
| `taskStatus` | `count`, `status`, `taskId`, `zones` |
| `traderLevel` | `level`, `traderId` |
| `traderStanding` | `compareMethod`, `traderId`, `value` |
| `useItem` | `compareMethod`, `count`, `useAnyItemIds`, `zones` |
| `visit` | `requiredKeyItemIds`, `zones` |

`wearing` is reduced to `wearingItemIds` (arrays of item ids); upstream also
embeds each worn item's name, which is dropped because the item dataset is the
source of names. `zones[].map` becomes `zones[].mapId`; a zone keeps its own
`id`, geometry and optional `name`. `possibleLocations[].map` becomes `mapId`.

## Dropped fields in the fixtures

`items` drops 138 fields, all from the prescribed trader-offer shape:
`buyFromTrader[].currencyItem`, `restockAmount`, `taskUnlock` and
`sellToTrader[].currencyItem`.

`tasks` drops 17: 16 embedded worn-item `name` values and one upstream
`craftUnlock.trader_name` that the schema does not model. Every other dataset
drops zero fields.

## Produce and verify

```bash
cd pipeline
npm run normalize -- --all                 # dist/normalized/<dataset>.jsonl
npm run normalize -- --dataset items --out /tmp/normalized
npm test                                   # golden + invariant suite
```

The CLI localizes and validates each committed fixture offline, normalizes it,
writes the JSONL, and prints per-kind counts, output bytes, dropped-field
counts and fallbacks.
