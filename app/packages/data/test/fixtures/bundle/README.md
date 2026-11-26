# Ingestion fixture bundle

A tiny, offline `regular` bundle used by the ingestion integration tests
(`test/sync/dataset_ingestor_test.dart`). It is a real slice of the committed
pipeline output, not a hand-invented schema:

- `items.jsonl.zst` — 7 records copied verbatim from
  `test/fixtures/normalized/items.jsonl` (the normalizer golden for the
  `regular` upstream fixture):
  `item` M4A1 `5447a9cd4bdc2dbd208b4567`, `item` M855 ammo pack
  `5447ac644bdc2d6c208b4567`, two `armorMaterial` records, one `playerLevel`,
  one `setting` and the `fleaMarket` record.
- `tasks.jsonl.zst` — 4 records copied verbatim from
  `test/fixtures/normalized/tasks.jsonl`: the `task` "Debut"
  `5936d90786f7742b1420ba5b`, the `task` "Postponed Reward [PVP ZONE]"
  `67e993f5ed537409f009da75`, one `achievement` and one `questItem`.
- `manifest.json` — built with the same arithmetic as the pipeline writer:
  SHA-256 over the compressed frame, exact compressed/uncompressed sizes and
  line counts, `generatedAt` fixed so the fixture is reproducible.

Provenance: the upstream payloads were captured from `https://json.tarkov.dev`
on 2026-11-25 (see `test/fixtures/README.md` and the repository `NOTICE`).
Compression: Node 26 `zlib.zstdCompressSync`, level 3, no worker threads, no
frame checksum — exactly the settings in `docs/data-bundles.md`.

To regenerate after re-capturing the normalized goldens, select the ids above
from `test/fixtures/normalized/`, compress each dataset to
`<dataset>.jsonl.zst`, and recompute the manifest fields. The whole directory
stays under 10 KB; the two compressed datasets total 4,826 bytes.

The tests also build synthetic bundles at runtime (using `archive`'s
`ZstdEncoder`) for unknown record kinds, corrupt JSONL, missing files and a
record-count mismatch, so no failure fixture is committed here.
