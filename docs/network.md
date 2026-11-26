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
| `github.com` | The stable per-mode manifest URL, `https://github.com/Tayuha/tarkov-companion/releases/download/data-<mode>-latest/manifest.json`. It is also the release page the app opens when an app update is available (no silent self-updater). |
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

The app is expected to contact only:

- the stable manifest URL on `github.com` (and the GitHub asset host it redirects to);
- per-dataset `.jsonl.zst` URLs resolved relative to that manifest (same GitHub hosts);
- image URLs on `assets.tarkov.dev` from the dataset.

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

```bash
cd app
dart test packages/data/test/net/allowlisted_http_client_test.dart
dart run tool/check_architecture.dart
```

The tests cover the exact allowlist contents; rejection with zero inner-client calls for a disallowed host, a
lookalike or subdomain, an empty host, URL credentials, and plain HTTP; the user-agent and 2xx body; a
`404`; timeouts; redirects to an allowed host; rejection of a disallowed redirect hop and of a
protocol-relative redirect; the redirect limit; relative `Location` resolution; an HTTPS-to-HTTP
downgrade; and the streaming `send` path (unbuffered body, allowlist pre-flight, redirect body drained
before the next hop, non-2xx status error).
