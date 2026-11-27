# Network access

Tarkov Companion is local-first and collects **no telemetry, analytics, crash reports, or usage data**.
It requires no account and sends no personal information. The only network requests it can make are the
data and image downloads needed to keep the local dataset current and to render item artwork.

This document is the allowlist that makes that claim auditable. The executable form is
[`NetworkAllowlist.productionHosts`](../app/packages/data/lib/src/net/host_allowlist.dart) and
[`AllowlistedHttpClient`](../app/packages/data/lib/src/net/allowlisted_http_client.dart); a change to the
hosts or rules here must change both, plus the tests in
[`app/packages/data/test/net/`](../app/packages/data/test/net/allowlisted_http_client_test.dart).

## Allowed hosts

Exactly these hosts are permitted. Matching is **case-insensitive and exact**: `github.com` does not
allow `api.github.com`, `github.com.evil.example`, `evilgithub.com`, or any subdomain.

| Host | Why the client needs it |
|---|---|
| `github.com` | The stable per-mode manifest URL, `https://github.com/Tayuha/tarkov-companion/releases/download/data-<mode>-latest/manifest.json`. The client has no self-updater and does not open the release page; an incompatible manifest only raises a compatibility error. |
| `objects.githubusercontent.com` | GitHub answers a release-asset download with a redirect to this CDN host. The manifest and the `.jsonl.zst` dataset bytes are served from here. |
| `release-assets.githubusercontent.com` | The newer GitHub release-asset CDN host. GitHub has used both asset hosts and can move a download between them, so both must be allowed for the same release URL to keep working. |
| `assets.tarkov.dev` | Item, task, and category images (`iconLink`, `imageLink`, `gridImageLink`, ...) referenced by the tarkov.dev dataset. |

Not allowed, deliberately:

- `json.tarkov.dev` and the rest of `tarkov.dev` — upstream API access belongs to the pipeline
  (`pipeline/`), never to the installed app.
- `raw.githubusercontent.com`, `api.github.com`, GitHub's web UI/API hosts, and every other GitHub
  subdomain.
- Any analytics, crash-reporting, advertising, or push/notification service. None is integrated and none
  is reachable.

The list is the same for every game mode, platform, and feature. Adding a host is a security and privacy
change: update the constant, this table, and the tests, and treat it as part of the periodic network audit
in task 9.4.

## Text-only hosts

These strings appear in the interface as unformatted text. They are not links, and no code path requests
them:

- `tarkov.dev` — the About screen prints the community project URL as plain text. Only its
  `assets.tarkov.dev` image host is on the request allowlist.

`docs/network.md` is the only documentation source the audit script reads, so a new display-only host must
be recorded here as well as in the UI copy.

## Destinations, triggers and payloads

The current client has three request shapes. None sends a request body, a cookie, an account token, or a
device identifier.

| Destination | Purpose | Trigger | Request | Response |
|---|---|---|---|---|
| `https://github.com/Tayuha/tarkov-companion/releases/download/data-<mode>-latest/manifest.json` | Fetch the versioned manifest for `regular`, `pve`, or `pvp-season`. | First-run gate `prepare`, a scheduled background update check, **Check now**, or a retry after an offline/upstream error. | `GET`; `Accept`, `Accept-Encoding: identity`, the client `User-Agent`, and `If-None-Match` / `If-Modified-Since` when a cached manifest is revalidated. | `200` with manifest JSON, `304` when unchanged, or a typed status error (`404`, `5xx`). |
| `objects.githubusercontent.com` or `release-assets.githubusercontent.com` | Serve the manifest bytes and each changed `.jsonl.zst` dataset after GitHub redirects the release-asset URL. | The same manifest request, and a dataset download when `prepare` finds a dataset that is not current. | `GET`; no body; the client re-applies the allowlist and the HTTPS rule to every redirect hop. | Manifest JSON or compressed JSONL bytes. Each dataset is length-checked and SHA-256-checked against the manifest before ingestion. |
| `assets.tarkov.dev` | Item, task, and category artwork referenced by `iconLink`, `imageLink`, `gridImageLink`, and similar bundle fields. | Building a visible item row or item detail with an image cache. The cache reads disk first and fetches only on a miss. | `GET`; no body, no cookies. | Image bytes stored in the bounded disk cache and rendered by the widget. A failed fetch renders the placeholder, not an error. |

### Wiring status in the preview build

The manifest and dataset paths are wired through `AppSessionReady.sync`. The image cache
(`ItemImageCache` and `AllowlistedItemImageFetcher`) is implemented and unit-tested, but the preview shell
does not yet pass an `ItemImageCache` to `HomeShell`; the current build therefore makes no
`assets.tarkov.dev` request and renders item placeholders. The host stays on the allowlist because it is
the only destination the cache may use once it is wired. See
[`verification.md`](verification.md) for the resulting manual-check status.

## Rules enforced by the client

`AllowlistedHttpClient` wraps a `package:http` client and applies these checks **before** a request is
handed to the transport, so a rejected destination produces zero network traffic (the tests count inner
client calls to prove it):

1. **HTTPS only.** A URI whose scheme is not `https` raises `InsecureSchemeException`. Plain HTTP is
   never attempted. The single exception is an explicit, test-only constructor option
   (`allowInsecureLocalhost: true`) that permits `http://127.0.0.1`, `http://[::1]`, or
   `http://localhost` **only** when the loopback host also appears in the supplied allowlist. It defaults
   to `false` and is used only by the first-run integration test; see [`first-run.md`](first-run.md).
2. **No URL credentials.** A URI with `user:password@` raises `UserInfoNotAllowedException` instead of
   silently sending them.
3. **A host must be present and listed.** An empty host or a host outside the table raises
   `DisallowedHostException`. The check runs on the original URI and again on every redirect target.
4. **GET only.** The client exposes `get`/`getText`/`getBytes` (buffered) and
   `send` (streamed); there is no API for other methods.
5. **Bounded time and redirects.** Each send and each buffered body read is limited by a timeout (30 s
   by default); a redirect chain may follow at most 5 hops. A streamed body is read under the caller's
   policy — `DatasetDownloader` applies the client's timeout as an idle read timeout. Exceeding either
   limit raises a typed error.
6. **Buffered or streamed bodies, never truncated.** `get` exposes the status, lowercased headers, the
   complete `bodyBytes` (`Uint8List`), and the final URI after redirects. `send` exposes the same
   status, headers and final URI with an unbuffered, single-subscription `Stream<List<int>>`; the
   dataset downloader uses it so a multi-megabyte asset never has to fit in memory. A non-2xx final
   status raises `HttpStatusException`, so a caller can distinguish `404` (missing manifest or asset)
   from `304` (unchanged manifest) and `5xx` (upstream outage).

## Redirects

`package:http`'s automatic redirect handling is disabled on every request (`followRedirects = false`,
`maxRedirects = 0`). The client follows redirects itself so it can re-apply the allowlist to each hop:

- `301`, `302`, `303`, `307`, and `308` are followed; any other status is returned or raised as a status
  error.
- `Location` is resolved with `Uri.resolve`, so absolute, root-relative, and path-relative locations all
  work. A relative asset name resolves next to the manifest, as described in
  [`data-bundles.md`](data-bundles.md#client-resolution).
- **Every** hop must be HTTPS and on the allowlist. A redirect to an unknown host raises
  `DisallowedHostException`; a redirect from HTTPS to HTTP raises `InsecureSchemeException`. In both
  cases the request is rejected before the next request is sent.
- At most 5 redirects are followed per call; the sixth response raises `TooManyRedirectsException`.
  A redirect status without a usable `Location` is a `HttpStatusException`.
- The body of every redirect response is drained before the next hop is requested, so the connection is
  released instead of carrying unread bytes. A final non-2xx body is drained the same way before
  `HttpStatusException` is thrown.
- Caller headers are reduced on a redirect to a safe, non-credential subset (`accept*`, `range`, and the
  `If-*` conditional headers). `Authorization` and `Cookie` are never forwarded to a redirect target.
  The conditional headers are kept so the sync layer can revalidate a manifest with `If-None-Match` after
  GitHub redirects to its asset CDN.

The normal chain is one or two hops:

```
https://github.com/Tayuha/tarkov-companion/releases/download/data-regular-latest/manifest.json
  -> 302 https://objects.githubusercontent.com/...        (or release-assets.githubusercontent.com)
  -> 200
```

## TLS

TLS verification is **not** weakened anywhere:

- The production client is `http.Client()`, which on the VM is `package:http`'s `IOClient` over `dart:io`'s
  `HttpClient`. `dart:io` validates the server certificate and hostname against the operating system
  trust store by default.
- The client never sets `badCertificateCallback`, never installs a permissive `SecurityContext`, and has
  no "ignore certificate errors" flag or fallback. A certificate failure surfaces as a
  `HandshakeException` and the request fails.
- The `innerClient` constructor parameter exists only so tests can inject `MockClient`. Application code
  must not pass its own client, because a custom client could weaken TLS.
- Certificate pinning is not used. GitHub's asset hosts rotate certificates on their own schedule, and a
  pinned certificate without a safe rotation path would brick data updates. The system trust store is the
  trust anchor, and bundle integrity is additionally enforced by the SHA-256 checksum from the manifest
  before any downloaded dataset is ingested (task 4.2).

## Requests the client makes

The client constructs exactly one URL itself: the stable manifest URL on `github.com`. Dataset URLs are
resolved relative to that manifest and therefore stay on the GitHub hosts above. Image URLs come from the
dataset and may target `assets.tarkov.dev` only; the image cache is not yet wired into the preview shell,
as described above. No other URL builder exists in `app/lib` or `app/packages/*/lib`.

The `User-Agent` identifies the app and its repository:
`tarkov-companion/0.1.0 (+https://github.com/Tayuha/tarkov-companion)`. No cookies are persisted, no
authentication token is stored by the client, and no referrer or device identifier is sent.

## Typed errors

| Error | Meaning |
|---|---|
| `DisallowedHostException` | Empty host, or host not in the allowlist (original URI or redirect hop). |
| `InsecureSchemeException` | URI or redirect target is not HTTPS. |
| `UserInfoNotAllowedException` | URI embeds credentials. |
| `TooManyRedirectsException` | Redirect chain exceeded the configured limit. |
| `HttpStatusException` | Final response status is outside `200..299`; `statusCode` carries the status. |
| `HttpTimeoutException` | A send or body read exceeded the timeout. |

Transport failures that are not timeouts (DNS, connection reset, TLS handshake) propagate as the
underlying `dart:io` exceptions rather than being disguised as policy errors.

## Verification

Static audit, from the repository root:

```bash
bash scripts/audit-network.sh
```

The script parses `NetworkAllowlist.productionHosts` and the “Allowed hosts” table above, fails when they
disagree, then scans production Dart sources for literal hosts. It makes no network requests and needs no
root. It is deliberately conservative: it catches `http(s)://` URLs and bare domains with common TLDs, not
every possible string that could be assembled into a host.

Automated policy tests:

```bash
cd app
dart test packages/data/test/net/allowlisted_http_client_test.dart
dart run tool/check_architecture.dart
```

A captured-request review (a proxy or packet capture while running a sync) remains a manual release-gate
step in [`verification.md`](verification.md).

The tests cover the exact allowlist contents; rejection with zero inner-client calls for a disallowed host, a
lookalike or subdomain, an empty host, URL credentials, and plain HTTP; the user-agent and 2xx body; a
`404`; timeouts; redirects to an allowed host; rejection of a disallowed redirect hop and of a
protocol-relative redirect; the redirect limit; relative `Location` resolution; an HTTPS-to-HTTP
downgrade; and the streaming `send` path (unbuffered body, allowlist pre-flight, redirect body drained
before the next hop, non-2xx status error).
