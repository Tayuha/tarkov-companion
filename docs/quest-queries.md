# Quest queries

The quest catalog reads the local database only. `QuestRepository`
(`app/packages/data/lib/src/quests/`) executes a `QuestQuery` and returns typed
`QuestSummary` rows, so a screen never sees drift rows, the stored payload or raw
`questProgress.state` strings.

- API: `QuestQuery`, `QuestFilters`, `QuestSort`, `QuestSummary`, `QuestPage`
- Repository: `QuestRepository.query` and `QuestRepository.count`
- Progress values: `QuestProgressState`
- Implementation: `app/packages/data/lib/src/quests/`

This is a read/query layer. It reports recorded progress; it does **not** derive
locked/available availability from prerequisites, level and progress. That is
the availability engine (see [`quest-tracking.md`](quest-tracking.md)).

## Usage

```dart
final repository = QuestRepository(database);

final page = await repository.query(
  const QuestQuery(
    profileId: 'profile-regular',
    filters: QuestFilters(
      text: 'punisher',
      traderId: '54cb50c76803fa8b248b4571',
      maxPlayerLevel: 20,
      state: QuestProgressState.notStarted,
    ),
    sort: QuestSort(QuestSortField.minPlayerLevel, descending: true),
    limit: 25,
    offset: 0,
  ),
);

for (final quest in page.quests) {
  print('${quest.name}: ${quest.progressState.name}');
}
print('${page.quests.length} of ${page.total}');
```

`QuestRepository.count(query)` returns `page.total` without reading a page.

## Filters

Every field is optional and filters combine with **AND**. `null` (or blank, for
text and ids) means "no constraint", so clearing one filter never disturbs the
others.

| Filter | Matches | Null/missing data |
|---|---|---|
| `text` | Quest name, case- and diacritic-insensitively. The text is split into Unicode letter/digit tokens; every token must be a substring of the bundle's `normalizedName`. | A hand-written record without `normalizedName` falls back to ASCII case-insensitive matching on `name`. Blank text is no filter; text with no token (`"---"`) matches nothing. |
| `traderId` | Exact upstream trader id. | Quests with no trader never match. |
| `mapId` | Exact upstream map id. | Quests with no map never match. |
| `minPlayerLevel` | **Exact** `tasks.minPlayerLevel` value. | A quest with an unknown required level never matches. |
| `maxPlayerLevel` | **At-or-below** bound: `tasks.minPlayerLevel <= value`. | A quest with an unknown required level never matches, because its gate cannot be proven. |
| `state` | The recorded state for `QuestQuery.profileId`. | A quest with no `questProgress` row is `notStarted`. See below. |

Set `minPlayerLevel` and `maxPlayerLevel` to the same value for "exactly this
level"; setting them to different values yields the intersection, so
`minPlayerLevel: 42, maxPlayerLevel: 9` matches nothing.

### Game-mode scoping

`QuestQuery.profileId` does more than read progress: when it names a real
profile, the query also keeps only tasks visible in that profile's
`profiles.gameMode`. A task payload's `gameMode` list is checked as follows:

- missing, empty, non-array or malformed -> visible in every mode (this keeps
  older bundles and hand-written fixtures readable);
- otherwise the list must contain the profile's mode (`regular`, `pve` or
  `pvp-season`).

`query` and `count` apply the same filter, and `statuses` / `availableQuests`
apply it in memory. Without a profile there is no active mode, so the catalog
is unscoped. An unknown profile id is also unscoped: the catalog has always
tolerated it and reports every row as `notStarted`. See
[`quest-tracking.md`](quest-tracking.md) for the user-facing rule.

### Search tokens

`questSearchTokens` lower-cases and folds Latin diacritics before splitting:

- `CAFÉ` -> `cafe`
- `"Café Crème"` -> tokens `cafe`, `creme`
- `"part 1"` -> tokens `part`, `1`; both must appear, in any order, so
  `The Punisher - Part 1` matches even though the text is not contiguous.

Only letters and digits become tokens, so FTS/punctuation characters in user
input cannot cause a syntax error or an accidental empty match.

## Progress state

`QuestProgressState` has four values. Only three are persisted:

| State | `questProgress.state` | Meaning |
|---|---|---|
| `notStarted` | no row | No progress recorded for the profile. |
| `inProgress` | `in-progress` | Started but not finished. |
| `completed` | `completed` | Finished. |
| `failed` | `failed` | Failed. |

- The state filter is scoped to `QuestQuery.profileId`; rows belonging to other
  profiles are ignored.
- With no `profileId`, no progress row can exist, so every summary is
  `notStarted` and only the `notStarted` state filter matches.
- An unrecognized stored value (for example an interrupted import) reads as
  `notStarted` and is included in the `notStarted` filter. It is never reported
  as progress the user did not record.

## Sorting

`QuestSort(field, descending:)` supports:

| Field | Order |
|---|---|
| `name` | The bundle's `normalizedName` (case/diacritic-insensitive), then quest id. |
| `minPlayerLevel` | Numeric required level. |
| `traderId` | Upstream trader id (not the trader's display name). |
| `mapId` | Upstream map id (not the map's display name). |

Rules:

- The default is ascending name.
- Ties are broken by normalized name ascending, then quest id ascending. This is
  independent of the primary direction, so a page is stable across calls and the
  same rows appear in the same order in both directions.
- Null values are last in **both** directions: "no trader/map/level" is not "the
  smallest trader/map/level".

## Pagination

`QuestQuery` carries `limit` and `offset`.

| Rule | Value |
|---|---|
| Default `limit` | 50 |
| Maximum `limit` | 200 |
| `limit < 1` | clamped to 1 |
| `limit > maxLimit` | clamped to 200 |
| `offset < 0` | clamped to 0 |

Clamping happens when `effectiveLimit`/`effectiveOffset` are read, so a stale
page number or a huge page size cannot throw mid-frame. `QuestPage.limit` and
`QuestPage.offset` report the clamped values actually used.

`QuestPage.total` is the count that matches the filters and **ignores**
`limit`/`offset`. `isEmpty` means "the filters match nothing"; `isPageEmpty`
means "this page is empty" (an offset past the end). `hasMore` and `nextOffset`
drive the next request.

## Where the name key comes from

The quest bundle already publishes `normalizedName` on every `task` record
(`docs/data-bundles.md`). The shipped schema has no `tasks.normalizedName`
column, and this task deliberately does not add one. The repository reads the
existing key from the canonical `tasks.payload` with `json_extract` and falls
back to `lower(name)` when it is absent.

Why this trade-off:

- The data already exists in the bundle and in every stored payload, so no
  schema version, migration, snapshot or ingestion change is needed.
- A few hundred quests make the JSON extraction immaterial; the count and page
  queries stay one SQL round trip inside a read transaction.
- If quest volume or query latency ever justifies it, promoting
  `normalizedName` to an indexed column is a small schema v6 migration. Search
  and sort semantics would not change.

Text search and name sorting intentionally use the same key, so the order a
user sees agrees with the search that produced it.
