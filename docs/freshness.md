# Price freshness

Prices and the item catalog age independently. A fresh bundle can carry an old
price (upstream had no new scan), and a catalog can be old while it still holds
the newest observation upstream ever produced. The app therefore never derives
price age from the dataset's apply time.

| Clock | Stored in | Means |
|---|---|---|
| Catalog freshness | `datasetState.appliedAt`, `datasetState.sourceUpdatedAt` | When this client applied the bundle, and when upstream fetched it. Used by the about screen and sync status. |
| Price freshness | `items.priceObservedAt` (from the bundle's `price.observedAt`) | When the newest price snapshot was observed upstream. Used by every price field. |

`price.observedAt` is the upstream `lastScan`
([`data-bundles.md`](data-bundles.md#price-object)). It is the newest
observation for that item, not a history entry. `priceHistory` (the on-demand
chart cache) has its own timestamps and TTL and does not participate in this
policy.

## The rule

`FreshnessPolicy.evaluate(observedAt, now)` in
`app/packages/data/lib/src/catalog/price_freshness.dart` returns a
`PriceFreshness`:

| Condition | Status | `age` | UI |
|---|---|---|---|
| No item, no `priceObservedAt`, or no price at all | `unknown` | `null` | Explicit "no recent data" state; no unqualified price |
| `age == threshold` | `fresh` | `age` | Price with its observation time |
| `age < threshold` | `fresh` | `age` | Price with its observation time |
| `age > threshold` | `stale` | `age` | Observation time **and** a stale label |
| `observedAt` is in the future | `fresh` | `0` | Price with its observation time |

The comparison is **strictly greater**: "older than the threshold" means
`age > threshold`. An observation exactly 24 hours old is fresh; 24 hours and
one second is stale. The boundary is covered by tests at 23 h 59 m, exactly
24 h, and 24 h + 1 s.

A future timestamp is treated as fresh with the age clamped to zero. The usual
cause is client clock skew, and labelling upstream data as outdated because of a
local clock would be wrong. A negative age is never shown.

`FreshnessStatus.unknown` is deliberately not `stale`: "we have no observation"
and "the observation is old" are different messages, and the price UI shows the
first as a missing-data state (spec: "Missing flea price", "distinct from a
price of zero").

## Threshold

The threshold comes from the `dataFreshnessHours` setting (default **24 h**,
allowed range 1–168 h):

```dart
final settings = await SettingsRepository(db).read();
final policy = FreshnessPolicy.fromSettings(settings);
final verdict = await ItemsRepository(db).priceFreshness(itemId, policy, now);
```

Changing the setting changes the verdict immediately; it does **not** require a
new download or re-ingestion, because the policy is evaluated against the stored
observation time. `FreshnessPolicy.defaults()` is the 24-hour policy for callers
that run before settings are loaded.

## UI obligation

A price is only meaningful with the time it was observed:

- Show `observedAt` next to the price. `PriceFreshness.requiresObservationTime`
  is true whenever a known observation exists.
- When `isStale`, show the observation time **and** a visible stale indicator.
  Never render a stale value as the current flea price (data-sync spec: "Price
  freshness is distinct from catalog freshness").
- When `isUnknown`, show an explicit missing-data state instead of a price.
  Trader prices that are present remain visible.

The data layer exposes the verdict, not a label: wording, icon and layout belong
to the catalog UI (task 5.5). These rules apply to the catalog rows as well as
the item detail view.

## Price-history cache TTL

The on-demand chart cache (`priceHistory`, task 5.7) has a **separate** TTL
from the freshness policy above. `PriceHistoryRepository` defaults to 6 hours
and measures expiry from the newest stored observation, because the bundle
contract has no history dataset and the cache table has no fetch timestamp; the
alternative would be a schema migration for a cache. A snapshot whose newest
point is already older than the TTL is therefore refetched on the next online
visit. Offline reads ignore the TTL: a stale cache is still shown, labelled
stale, instead of pretending there is no history. No cache offline is the
explicit unavailable state in `PriceHistoryChart`.

## Detail price states

The item detail panel (task 5.5) renders three distinct states and never
collapses them:

| State | Condition | Rendering |
|---|---|---|
| Complete | `lastLow` and/or `avg24h` present | Rouble values, 48 h direction, observation timestamp, base price |
| Missing flea | both flea fields `null` | `No flea price observed yet.` (or `Not available on the flea market.` for a `noFlea` item) |
| Zero | `lastLow == 0` | `No flea offers (0 ₽)`; not treated as missing |

A trader-only item keeps its base price even when the flea fields are absent,
matching the rule that "we have no observation" is not the same as "the
observation is old".
