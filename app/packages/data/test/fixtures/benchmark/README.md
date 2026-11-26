# Full items ingestion benchmark fixture

A real `regular` items asset from the live `data-regular-latest` release, kept
byte-identical to what the app downloads. It backs the `benchmark`-tagged test
`test/sync/ingest_benchmark_test.dart`; nothing here is generated or edited.

## Provenance

| Field | Value |
|---|---|
| Repository | `Tayuha/tarkov-companion` |
| Release tag | `data-regular-latest` |
| Release published | 2026-11-26T10:30:13Z |
| Downloaded | 2026-11-26 |
| Asset | `items-ed751dcd264d.jsonl.zst` |
| Asset bytes | 1,433,154 (1,367 KiB / 1.37 MiB) |
| Asset SHA-256 | `ed751dcd264d08fceeea2029ba47b5e03a07e8674a094f3ada562a776a188195` |
| Manifest SHA-256 | `511fc31f8921238606b64bcef7dccd487e9052be9cdecc612911ecb4c8a18e01` |
| Manifest records | 6,015 lines, of which 5,498 are `kind == "item"` |
| Uncompressed bytes | 17,417,643 |

The asset checksum is the checksum the published manifest declares, so the bytes
are exactly what a client verifies and ingests. `manifest.json` is the complete
published document for `regular`; only the `items` entry's asset is committed
here, so the other `path` values in the manifest point at assets that are not in
this directory. The benchmark reads only the `items` entry.

## Download

```bash
gh release download data-regular-latest -R Tayuha/tarkov-companion \
  -p 'manifest.json' -p 'items-ed751dcd264d.jsonl.zst' -D app/packages/data/test/fixtures/benchmark/
sha256sum app/packages/data/test/fixtures/benchmark/manifest.json \
  app/packages/data/test/fixtures/benchmark/items-ed751dcd264d.jsonl.zst
```

The release also carries an older items asset (`items-577997cb4afd`) from a
previous build. It is intentionally not committed: the manifest points at
`items-ed751dcd264d`, and the benchmark must ingest the asset a client would
actually download.

## Refreshing the snapshot

The fixture is a point-in-time snapshot, not a live download. When the published
`items.jsonl.zst` changes, replace it deliberately:

1. Read the current `datasets[]` entry named `items` from
   `https://github.com/Tayuha/tarkov-companion/releases/download/data-regular-latest/manifest.json`
   and note its `path` (`items-<sha12>.jsonl.zst`).
2. Download that exact asset and the manifest into this directory with the
   `gh release download` command above (change the file name).
3. Delete the old `items-*.jsonl.zst` and update the table and the record counts
   here. Verify the asset's SHA-256 equals the manifest's `sha256` and its size
   equals `compressedBytes`.
4. Run `cd app && dart test packages/data -t benchmark -j 1` and update the
   measured numbers in `docs/benchmark.md` and the constants in the benchmark
   test if the dataset size changed materially.

Do not recompress, trim, reformat or re-serialize the asset: the benchmark's
size and checksum assertions are about the real published bytes.

## Size note

The whole `regular` bundle (all seven datasets) is ~2.36 MB compressed today;
this one items asset is 1.37 MiB. It sits well inside the 10 MiB per-mode
budget from design D7, with room for maps (0.60 MiB), tasks (0.23 MiB) and the
small datasets. The compressed-size assertion protects the items slice, which is
the largest single contributor and the one that grows when upstream adds items.
