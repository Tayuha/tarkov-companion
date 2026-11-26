# Data sync

The `data-sync` workflow keeps the three rolling data releases current. It
fetches the upstream API, validates every dataset against its Zod schema,
normalizes it to bundle JSONL, compares the result with what is already
published, and publishes only when a client would actually download different
bytes.

The byte-level contract (layout, checksums, asset names, manifest fields) is in
[`data-bundles.md`](data-bundles.md). This page covers operations.

## Schedule and manual runs

| Trigger | When |
|---|---|
| `schedule` | `0 */6 * * *` — every 6 hours, UTC. GitHub may start scheduled runs late during peak load. |
| `workflow_dispatch` | Any time, from the Actions tab or `gh`. |

The job has a 30-minute timeout, `contents: write` (release assets) and
`issues: write` (failure issue). It never runs on pull requests, and
`concurrency: { group: data-sync, cancel-in-progress: false }` queues a second
run instead of cancelling a publication mid-manifest-swap.

```bash
gh workflow run data-sync.yml --ref main
gh run list --workflow data-sync.yml --limit 5
gh run watch <run-id>
gh run view <run-id> --log
```

Every run exercises all three modes: `regular`, `pve` and `pvp-season`. For each
mode it processes `items`, `tasks`, `traders`, `hideout`, `crafts`, `barters`
and `maps`.

## What a run does

1. **Fetch** each `{mode, dataset}` with the conditional cache. A `200` returns
   the localized payload; a `304` proves the content did not change.
   Localization follows the declared JSONPath pointers and then applies a
   dictionary-keyed fallback for placeholder-shaped strings no pointer selects
   (upstream occasionally adds a translatable field before its pointer). The
   fallback never rewrites identity fields; an unknown placeholder still blocks
   validation.
2. **Validate** the localized payload with the registry schema. A failure blocks
   the whole mode.
3. **Normalize** to bundle records and persist the JSONL in the normalized cache
   under its upstream content checksum.
4. **Bundle** the mode once every dataset is ready, then compare it with the
   published manifest.
5. **Publish** changed dataset assets first and `manifest.json` last. No change
   means zero create/upload/delete calls.

### Partial failure

All modes are attempted even when one fails, and the process exits `1` with a
summary. A failure anywhere before the manifest swap leaves the previous
manifest live: clients keep reading the old manifest and its immutable,
content-addressed assets.

A dataset that fails validation or normalization blocks its **entire mode**.
Publishing the remaining datasets would mark the failed one as `removed` in the
manifest and make clients delete its rows. The other modes are still published.

The CLI writes `pipeline/dist/sync-report.json` with the per-mode counters and
the first error, which the workflow uses to name the failed mode/dataset in the
issue.

## Cache behavior

The workflow restores and saves `pipeline/.cache/pipeline` with
`actions/cache@v4`:

- key: `pipeline-cache-<run-id>` (immutable per run);
- restore prefix: `pipeline-cache-` (the newest previous run wins).

The directory holds two caches:

| Cache | Key | Purpose |
|---|---|---|
| Upstream metadata | `{mode, dataset, lang}` | ETag / Last-Modified validators, localized content checksum, fetch time. |
| Normalized JSONL | `{mode, dataset, lang, checksum}` | The exact normalized records for that upstream checksum, so a fresh runner can rebuild a bundle from a `304` without downloading. |

If a `304` arrives but the normalized entry is missing (cold cache, eviction),
the run logs the decision and retries that dataset **unconditionally** once. The
new payload is validated and normalized as usual. A damaged or missing cache
entry is always a cache miss, never a failure.

The normalized key includes `NORMALIZED_CACHE_VERSION`. Bump it when the bundle
record contract changes incompatibly so old entries become unreachable.

## Releases and tags

Each mode publishes to one rolling release. The tag names and asset layout are
frozen by the publication contract:

| Mode | Tag |
|---|---|
| `regular` | `data-regular-latest` |
| `pve` | `data-pve-latest` |
| `pvp-season` | `data-pvp-season-latest` |

The stable pointer is
`https://github.com/Tayuha/tarkov-companion/releases/download/data-<mode>-latest/manifest.json`.
Assets are `manifest.json` plus `<dataset>-<sha12>.jsonl.zst`.

## Failure issue lifecycle

There is exactly one issue, titled **Data sync failing**, labelled `data-sync`.

- **Failure** (`if: failure()`): create the issue, or reopen it and add a comment
  when a previous failure is still closed. The body carries the run URL, the
  failed mode/dataset when
  `pipeline/dist/sync-report.json` can be read, the error message, and the last
  60 lines of the log (capped at 6000 characters).
- **Success** (`if: success()`): close the issue with a short comment when it is
  open; do nothing when it is already closed or absent.

The reporter is `pipeline/src/ci/report-status.ts`. It calls `gh` through
`execFile` (argument vectors, no shell) and is unit-tested with a fake runner.

## Forcing a refresh

A normal run trusts the conditional cache. To re-download and re-normalize every
dataset regardless of validators:

```bash
cd pipeline
npm run sync -- --all --force
```

`--force` skips `If-None-Match` / `If-Modified-Since` for both the dataset and
its dictionary, then overwrites the normalized entry for the same checksum. Use
it after a normalizer fix: otherwise a `304` would legitimately reuse the
normalized JSONL produced by the previous code.

Other flags:

| Flag | Meaning |
|---|---|
| `--mode <mode>` | One mode instead of all (cannot be combined with `--all`). |
| `--all` | Every mode. This is the default when `--mode` is omitted. |
| `--dry-run` | Build and plan only. With a release client it reads the published manifest; no mutation. |
| `--cache-dir <dir>` | Override `.cache/pipeline`. |
| `--out <dir>` | Bundle output root (default `dist/bundles`). |
| `--fixtures <dir>` | Offline source. Requires `--dry-run`. |
| `--report <file>` | Report path (default `dist/sync-report.json`; not written in dry-run). |

Offline verification against the committed fixtures, with no network and no
release access:

```bash
cd pipeline
npm run sync -- --all --fixtures ../test/fixtures/upstream --dry-run
npm test
```

## Rolling back a bad bundle

Publications are forward-only; the release has no "previous version" pointer.
Content-addressed dataset assets are never deleted on a normal publish, so the
bytes of the last good bundle usually still exist. To roll back:

1. Revert the pipeline commit that produced the bad data, or fix the normalizer.
2. Bump `NORMALIZED_CACHE_VERSION` if the record shape changed.
3. Republish with a forced refresh:

   ```bash
   cd pipeline
   npm run sync -- --all --force
   ```

For an emergency pointer-only rollback, keep a copy of the last good
`manifest.json`; re-uploading it with `gh release upload <tag> manifest.json
--clobber` makes clients resolve the old, immutable dataset assets again. Do this
only when those assets are still present — pruning removes them.

Never delete or edit dataset assets by hand: clients cache exactly one manifest
and trust its checksums.
