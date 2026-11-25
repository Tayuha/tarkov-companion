# Pipeline

Normalizes `json.tarkov.dev` data into versioned bundles for the app. See
[`../openspec/changes/bootstrap-tarkov-companion/design.md`](../openspec/changes/bootstrap-tarkov-companion/design.md)
for the architecture and [`../NOTICE`](../NOTICE) for attribution.

## Status

Implemented so far:

- Minimal JSONPath resolver for the upstream `translations` pointers (`$`, `.key`, `.*`, `[n]`, `[*]`,
  `..key`, `..*`, `['a','b']`).
- Locale dictionary lookup and in-place resolution with diagnostics.
- Fetch helper with timeouts, retries, user agent, and strict dictionary handling.
- CLI to inspect any dataset.
- Deterministic, committed upstream fixtures for the pipeline tests (`test/fixtures/upstream/`).
- Zod schemas for every captured dataset, with a registry keyed by `{mode, dataset}` and an offline
  fixture-validation CLI.

Not implemented yet: normalization, bundle writing, publication, conditional requests. Those are tracked
in `openspec/changes/bootstrap-tarkov-companion/tasks.md`.

## Usage

```bash
npm ci
npm test
npm run lint
npm run build
npm run validate:fixtures   # offline: parse every committed fixture through its schema

# Inspect a dataset with real data
npm run fetch -- --dataset traders --sample 3
npm run fetch -- --dataset items --sample 3 --out /tmp/items.localized.json

# Refresh the committed upstream fixtures (network; rewrites test/fixtures/upstream/)
npm run fixtures
```

Options: `--mode regular|pve|pvp-season`, `--dataset <name>`, `--lang <code>` (default `en`),
`--base-url <url>`, `--out <file>`, `--sample <n>`.

Fixtures keep unresolved placeholders plus a filtered `_en` dictionary so tests exercise the
resolver. See [`../test/fixtures/README.md`](../test/fixtures/README.md) for the trimming policy,
layout, budget, and stale-pointer notes.

## Schema validation

Upstream payloads are validated with Zod before normalization. One module per dataset, plus shared
primitives:

```
pipeline/src/schemas/
  primitives.ts   ids, timestamps, URLs, prices, vectors, item filters
  envelope.ts     { data, translations? } and { data: Record<string, string> }
  items.ts        /{mode}/items (named collections, property unions)
  tasks.ts        /regular/tasks (+ questItems, achievements, prestige)
  traders.ts      /regular/traders (id-keyed)
  hideout.ts      /regular/hideout (id-keyed)
  crafts.ts       /regular/crafts (array)
  barters.ts      /regular/barters (array)
  maps.ts         /regular/maps (maps, mobs, loot containers, …)
  prices.ts       /regular/prices/{itemId} (array)
  status.ts       /common/status
  season.ts       /pvp-season/season
  registry.ts     {mode, dataset} -> schema, envelope, counts
  fixtures.ts     offline fixture discovery helpers
```

`registry.ts` is the only place that maps a fixture to a schema. The test suite fails if a fixture
directory/dataset has no schema, or if a registered schema has no fixture, so a newly captured dataset
cannot slip through unvalidated.

Strictness policy:

- Objects are **loose**: unknown upstream fields are preserved and ignored, so a new field never breaks
  a build. Known fields are strictly typed; a missing required field or a retyped one fails with a Zod
  path naming it.
- Fields selected by a discriminator (`ItemProperties*.propertiesType`, task objective `type`) are
  typed but optional unless the fixture shows them on every record. The committed fixtures are trimmed
  snapshots, so requiring every per-type field would reject valid upstream records.
- Nulls and `nullish` are only used where a fixture justifies them: nullable price fields, task `map`,
  barter `taskUnlock`, trader multipliers, season `points`, prestige customization `imageLink`, and
  the few objective fields that are both absent and `null`.
- Entity references (item, task, trader ids) are validated as non-empty strings, never checked for
  existence: a fixture may reference a record trimmed out of another dataset.
- Empty arrays are always valid.

```bash
npm run validate:fixtures
```

The CLI parses every committed base fixture and every dictionary, prints per-dataset record counts, and
exits non-zero on the first schema regression. It performs no network I/O.

## Localization contract

The upstream payload carries unresolved keys plus a list of JSONPath pointers:

```json
{
  "data": { "5447a9cd...": { "name": "5447a9cd... Name" } },
  "translations": ["$.data.items.*.name"]
}
```

The dictionary is a flat map keyed by the placeholder string:

```json
{ "data": { "5447a9cd... Name": "Colt M4A1 5.56x45 assault rifle" } }
```

`localizeInPlace` walks each pointer and swaps matching strings. It never throws on a stale or unparsable
pointer; it records them in `stats` so the pipeline can decide whether to publish.

### Diagnostics

| Field | Meaning |
|---|---|
| `translated` | Strings replaced from the dictionary |
| `missingKeys` | Placeholder-shaped strings with no dictionary entry |
| `unresolvedPaths` | Pointers that matched nothing (stale metadata) |
| `failedPaths` | Pointers outside the supported grammar |
| `unmatched` | Selected strings that were already final text |

Measured on 2026-11-25 for `regular/en`: items 25,016 strings, tasks 3,642, traders 32, all with zero
missing keys. Known gaps: 13 stale task pointers and reward customization names absent from the
dictionary.

## API

```ts
import { fetchDataset } from "./src/upstream/fetch.js";

const { data, stats, warnings } = await fetchDataset({ mode: "regular", dataset: "items" });
```

`fetchDataset` mutates its own parsed payload and returns `data` ready for normalization. Pass
`allowMissingDictionary: true` only for diagnostics; the default fails closed so untranslated placeholders
never reach a bundle silently.
