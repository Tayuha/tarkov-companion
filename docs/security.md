# Security model

This page describes what Tarkov Companion trusts, what it stores, and what it deliberately does not do.
It is the design context for [`SECURITY.md`](../SECURITY.md); the network boundary in detail is in
[`network.md`](network.md).

The current scope is the Linux `0.1.0` preview. Windows and Android builds are compiled for
compatibility checks but are not packaged or supported releases.

## Trust boundaries

| Component | Trust |
|---|---|
| Local SQLite database | Trusted once opened. A failed open is handled read-only, never deleted. |
| Downloaded manifest and datasets | Untrusted bytes until the length and SHA-256 in the manifest match. Schema version and game mode are also checked before ingestion. |
| Upstream API (`json.tarkov.dev`) | Used only by the offline pipeline when maintainers publish a bundle. The installed app never contacts it. |
| GitHub Releases | The distribution channel for manifests and datasets. HTTPS plus the host allowlist; artifacts are unsigned. |
| Item images | Untrusted bytes rendered from the tarkov.dev image host. The cache writes only files derived from a URL hash and renders a placeholder on failure. |
| User exports | Trusted input only after parsing and validation; import defaults to a non-destructive merge. |

The app has no server, no accounts, and no remote state. There is no place for a stolen session token to
exist because none is issued or stored.

## Data at rest

On Linux the data root is `${XDG_DATA_HOME:-$HOME/.local/share}/tarkov_companion`:

```
db/tarkov_companion.sqlite   game data, profiles, progress, settings
db/backups/                  pre-migration copies
downloads/<mode>/            verified .jsonl.zst bundles
logs/app*.log                rotating local diagnostics
```

Player progress is stored only in that database and in files the user explicitly exports. The app does
**not** add database encryption, a passphrase, or a keyring dependency. Protection at rest is the operating
system account and the permissions of the data directory; a shared account or a copied file is outside the
app's control.

Diagnostics are local JSON-lines records. They are not uploaded automatically. Exported progress files
contain quest and objective progress and should be treated as personal data.

## Network

The only permitted destinations are the four hosts in [`network.md`](network.md). The client:

- uses HTTPS only, with the system trust store and no certificate-error override;
- rejects URL credentials, empty hosts, and unlisted hosts before a request is created;
- re-checks every redirect hop and drops credentials on redirect;
- sends no cookies, authentication token, referrer, or device identifier;
- collects no telemetry, analytics, crash reports, or usage data.

There is no silent self-updater. A manifest that requires a newer app raises a compatibility error; it does
not download or execute an installer.

## Download integrity

Before a dataset is ingested, `DatasetDownloader` verifies:

1. the response is a 2xx HTTPS response on an allowed host;
2. the byte count matches the manifest's `compressedBytes`;
3. SHA-256 matches the manifest's `sha256`;
4. the dataset name, mode, and schema version are compatible with this client.

A mismatch deletes the partial file and leaves the previously applied dataset in place. Ingestion runs in a
transaction, so a failure cannot leave a half-written game-data table.

Release artifacts are **unsigned**. The release notes state that status, and `SHA256SUMS` lets a user check
that a download is the artifact the release workflow produced. The checksum is not a signature: it protects
against corruption, not against a compromised release account.

## Database recovery

`openAppDatabase` reads `user_version` before drift touches the file. It takes a pre-migration backup with
`VACUUM INTO` when an upgrade is needed. If inspection or migration fails, or the file is newer than the
client supports, it returns `DatabaseRecovery`:

- the original file is kept byte-for-byte; nothing is deleted, truncated, or auto-restored;
- the file is reopened with SQLite `OpenMode.readOnly`, so the handle cannot modify it;
- the shell shows “Local database recovery” and a message that no data was deleted.

The current preview has no export action on that screen; this is recorded as a failed check in
[`verification.md`](verification.md). The recovery stack itself (read-only reads, refused writes, explicit
restore) is covered by `app/packages/data/test/migration_runner_test.dart`.

## Supply chain and dependencies

- Dart and Node dependencies are locked (`app/pubspec.lock`, `pipeline/package-lock.json`).
- CI runs analysis, tests, and packaging on the supported targets.
- The data pipeline consumes a public API and publishes derivative data; it does not distribute upstream
  server code.
- No official game art or game binaries are bundled. See [`NOTICE`](../NOTICE).

## Reporting

Do not open a public issue for a vulnerability. Use GitHub private vulnerability reporting as described in
[`SECURITY.md`](../SECURITY.md), and include the version, platform, reproduction steps, and impact.
