/// Typed failures raised by the allowlisted HTTP client.
///
/// Every error carries the URI it applies to, so a sync report or a log line
/// can name the destination without re-deriving it. Callers are expected to
/// match on the subtypes instead of parsing messages: in particular, a manifest
/// fetch distinguishes `404` through [HttpStatusException.statusCode].
library;

/// Base class for every error the allowlisted client raises.
///
/// Network transport failures that are not timeouts (DNS, connection reset,
/// TLS handshake) are deliberately **not** wrapped: they propagate as the
/// `dart:io` `SocketException`/`HandshakeException` they are, so a certificate
/// failure is never mistaken for a policy rejection or retried as one.
sealed class HttpClientException implements Exception {
  const HttpClientException(this.uri, this.message);

  /// The URI the failed request targeted.
  ///
  /// For redirect failures this is the original URI; the last hop is available
  /// on [TooManyRedirectsException.lastUri] and [HttpStatusException.uri].
  final Uri uri;

  /// Human-readable reason. Safe to log; never contains credentials.
  final String message;

  @override
  String toString() => '$runtimeType: $message ($uri)';
}

/// The host is not in the configured allowlist.
///
/// Raised before the request is handed to the inner HTTP client, so a
/// disallowed destination never produces network traffic.
final class DisallowedHostException extends HttpClientException {
  DisallowedHostException(Uri uri, {required String host})
    : host = host,
      super(
        uri,
        host.isEmpty
            ? 'The URI has no host.'
            : 'Host "$host" is not in the network allowlist.',
      );

  /// The rejected host exactly as it appeared in the URI.
  final String host;
}

/// The URI does not use HTTPS.
///
/// The client never speaks plain HTTP, and a redirect cannot downgrade a
/// request to it.
final class InsecureSchemeException extends HttpClientException {
  InsecureSchemeException(Uri uri)
    : super(
        uri,
        'Only HTTPS is allowed; the URI uses '
        '"${uri.scheme.isEmpty ? '(none)' : uri.scheme}".',
      );
}

/// The URI embeds credentials (`user:password@host`).
///
/// Credentials in a URL are both a privacy leak and an allowlist bypass
/// attempt; the client rejects them before resolving the host.
final class UserInfoNotAllowedException extends HttpClientException {
  UserInfoNotAllowedException(Uri uri)
    : super(uri, 'Credentials in a URL are not allowed.');
}

/// A redirect chain is longer than the configured limit.
final class TooManyRedirectsException extends HttpClientException {
  TooManyRedirectsException(
    Uri uri, {
    required this.maxRedirects,
    required this.lastUri,
  }) : super(
         uri,
         'Exceeded $maxRedirects redirect(s); the last hop was $lastUri.',
       );

  /// Maximum number of redirects the client was allowed to follow.
  final int maxRedirects;

  /// The URI of the hop that produced the redirect over the limit.
  final Uri lastUri;
}

/// The server answered with a status outside `200..299`.
///
/// Redirects are handled inside the client, so a caller only sees this for a
/// final response (for example `404` for a missing manifest, `304` for an
/// unchanged one, or a `5xx` outage).
final class HttpStatusException extends HttpClientException {
  HttpStatusException(this.statusCode, Uri uri)
    : super(uri, 'HTTP $statusCode response.');

  /// The response status code.
  final int statusCode;

  /// Whether the resource does not exist (or is not visible to the client).
  bool get isNotFound => statusCode == 404;

  /// Whether a conditional request found the document unchanged.
  bool get isNotModified => statusCode == 304;
}

/// The request or its body did not finish within the configured timeout.
final class HttpTimeoutException extends HttpClientException {
  HttpTimeoutException(Uri uri, this.timeout)
    : super(uri, 'Request timed out after ${timeout.inMilliseconds} ms.');

  /// The timeout that expired.
  final Duration timeout;
}
