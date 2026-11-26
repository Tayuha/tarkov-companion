# Test fixtures

## `manifest-regular.json`

A real published manifest, downloaded on 2026-11-26 with:

```bash
gh release download data-regular-latest -p manifest.json
```

Source release: `data-regular-latest` (Tayuha/tarkov-companion), whose stable
manifest URL is
`https://github.com/Tayuha/tarkov-companion/releases/download/data-regular-latest/manifest.json`.

It is trimmed to two datasets (`items`, `tasks`) so the fixture stays small;
every field of those entries and all provenance timestamps are the published
values. Only `datasets` and `totals` were shortened:

- `totals.datasets` = 2
- `totals.records` = 6,793
- `totals.compressedBytes` = 1,672,554
- `totals.uncompressedBytes` = 19,562,454

The JSON is pretty-printed for review; the published manifest is canonical JSON
with the same values. Tests never download anything.
