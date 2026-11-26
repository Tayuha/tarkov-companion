/// The documented set of hosts the client is permitted to contact.
///
/// This list is a privacy and safety boundary, not a convenience: the client
/// is local-first and collects no telemetry, so every destination it can reach
/// is written down here and in `docs/network.md`.
library;

/// Hosts the shipped client may contact.
///
/// Matching is case-insensitive and exact (no subdomain or suffix match). A
/// host that is not listed is rejected by `AllowlistedHttpClient` before any
/// request is created.
abstract final class NetworkAllowlist {
  /// The production allowlist.
  ///
  /// * `github.com` — the stable release-manifest URL
  ///   (`https://github.com/Tayuha/tarkov-companion/releases/download/...`)
  ///   and the release page that hosts app-update links. GitHub answers a
  ///   release-asset download with a redirect to a CDN host below.
  /// * `objects.githubusercontent.com` — one of the two hosts GitHub redirects
  ///   release-asset downloads to. It is where the manifest and the
  ///   `.jsonl.zst` dataset bytes are actually served.
  /// * `release-assets.githubusercontent.com` — the newer release-asset CDN
  ///   host GitHub redirects to. GitHub has used both names and may switch a
  ///   download between them, so both must be allowed for the same release URL
  ///   to keep working.
  /// * `assets.tarkov.dev` — item, task and category images referenced by the
  ///   tarkov.dev data (`iconLink`, `imageLink`, ...). Nothing else on
  ///   `tarkov.dev` is contacted: `json.tarkov.dev` is a pipeline-only
  ///   endpoint.
  static const Set<String> productionHosts = {
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
    'assets.tarkov.dev',
  };
}
