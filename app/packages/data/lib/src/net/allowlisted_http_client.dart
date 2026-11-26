import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'host_allowlist.dart';
import 'http_errors.dart';

/// A response returned by [AllowlistedHttpClient].
final class AllowlistedHttpResponse {
  AllowlistedHttpResponse({
    required this.statusCode,
    required Map<String, String> headers,
    required this.bodyBytes,
    required this.finalUri,
  }) : headers = Map.unmodifiable({
         for (final entry in headers.entries)
           entry.key.toLowerCase(): entry.value,
       });

  /// HTTP status code. Always in `200..299` for a response the client returns;
  /// other statuses are thrown as [HttpStatusException].
  final int statusCode;

  /// Response headers with lowercased names.
  final Map<String, String> headers;

  /// The complete response body. The client never truncates a body.
  final Uint8List bodyBytes;

  /// The URI that produced the body after following redirects.
  final Uri finalUri;

  /// Decodes [bodyBytes] as strict UTF-8.
  ///
  /// Malformed bytes throw a [FormatException]; callers that expect binary
  /// data should use [bodyBytes] instead.
  String get bodyText => utf8.decode(bodyBytes);
}

/// A 2xx response whose body has not been read yet.
///
/// Returned by [AllowlistedHttpClient.send]. The body is a single-subscription
/// stream: listen to it once, and cancel the subscription to abort the transfer
/// (which closes the underlying connection). Nothing is buffered by the client,
/// so a multi-megabyte dataset never has to fit in memory.
final class AllowlistedStreamedResponse {
  AllowlistedStreamedResponse({
    required this.statusCode,
    required Map<String, String> headers,
    required this.body,
    required this.finalUri,
  }) : headers = Map.unmodifiable({
         for (final entry in headers.entries)
           entry.key.toLowerCase(): entry.value,
       });

  /// HTTP status code. Always in `200..299`; other statuses are thrown as
  /// [HttpStatusException] by [AllowlistedHttpClient.send].
  final int statusCode;

  /// Response headers with lowercased names.
  final Map<String, String> headers;

  /// The response body. Single subscription; not buffered.
  final Stream<List<int>> body;

  /// The URI that produced [body] after following redirects.
  final Uri finalUri;
}

/// An HTTP client that can only reach a documented host allowlist.
///
/// The client is intentionally small: it exists to make the app's network
/// surface auditable. It supports one operation, `GET` — [get] buffers the
/// whole body, [send] streams it — and it enforces the policy before a request
/// reaches the transport:
///
/// * HTTPS only — plain HTTP is rejected, including as a redirect target;
/// * no credentials embedded in the URI (`user:password@host`);
/// * an exact, case-insensitive host match against [NetworkAllowlist];
/// * manual redirect handling, with every hop re-validated, a redirect limit,
///   and no downgrade to HTTP.
///
/// ## TLS
///
/// The production client is `http.Client()`, which on the VM is
/// `package:http`'s `IOClient` over `dart:io`'s `HttpClient`. That client
/// verifies the server certificate against the operating system trust store by
/// default. This class never sets `badCertificateCallback`, never lowers the
/// security context, and has no insecure fallback: a certificate failure is a
/// `HandshakeException` that propagates to the caller. Do not pass a custom
/// [innerClient] in application code; it exists so tests can inject
/// `MockClient`, and a custom client could weaken TLS.
///
/// ## Redirects
///
/// `package:http`'s automatic redirect following is disabled on every request.
/// The client reads `Location`, resolves it with [Uri.resolve] (so relative
/// locations work), validates the result against the same rules, and only then
/// sends the next request. The redirect response body is drained first, so the
/// connection is released before the next hop. A redirect to a host outside the
/// allowlist or to plain HTTP is rejected **before** that request is sent.
/// Caller headers are
/// reduced to a safe, non-credential subset on redirect so an `Authorization`
/// header is never forwarded to a CDN host; conditional headers such as
/// `If-None-Match` are preserved for later manifest caching.
///
/// ## Errors
///
/// Policy failures and bad responses are thrown as [HttpClientException]
/// subtypes. Transport failures that are not timeouts propagate unchanged.
final class AllowlistedHttpClient {
  AllowlistedHttpClient({
    http.Client? innerClient,
    Set<String>? allowlist,
    Duration timeout = defaultTimeout,
    String userAgent = defaultUserAgent,
    int maxRedirects = defaultMaxRedirects,
  }) : _allowlist = _normalizeAllowlist(allowlist),
       timeout = _validateTimeout(timeout),
       userAgent = _validateUserAgent(userAgent),
       maxRedirects = _validateMaxRedirects(maxRedirects),
       _inner = innerClient ?? http.Client();

  /// Default per-request and per-body timeout.
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Default `User-Agent`, identifying the app and its source repository.
  static const String defaultUserAgent =
      'tarkov-companion/0.1.0 (+https://github.com/Tayuha/tarkov-companion)';

  /// Default number of redirects a single [get] may follow.
  static const int defaultMaxRedirects = 5;

  static const Set<int> _redirectStatuses = {301, 302, 303, 307, 308};

  /// Headers that are safe to forward to a redirect target.
  ///
  /// Everything else — notably `Authorization` and `Cookie` — is dropped when
  /// the chain leaves the original request. The conditional headers are kept
  /// because a manifest request must be able to revalidate after GitHub's
  /// redirect to its asset CDN.
  static const Set<String> _redirectSafeHeaders = {
    'accept',
    'accept-encoding',
    'accept-language',
    'if-match',
    'if-modified-since',
    'if-none-match',
    'if-range',
    'if-unmodified-since',
    'range',
  };

  /// Headers a caller must not override: they either describe the connection
  /// rather than the resource, or would undermine the host check.
  static const Set<String> _forbiddenRequestHeaders = {
    'connection',
    'content-length',
    'host',
    'proxy-authorization',
    'transfer-encoding',
  };

  final http.Client _inner;
  final Set<String> _allowlist;

  /// Timeout applied to each request send and each body read.
  final Duration timeout;

  /// Value sent as the `User-Agent` header.
  final String userAgent;

  /// Maximum redirects one [get] may follow. Zero disallows redirects.
  final int maxRedirects;

  /// Sends a `GET` request and returns a 2xx response whose body is streamed.
  ///
  /// [headers] are sent on the first request only; on redirect the subset in
  /// [_redirectSafeHeaders] is forwarded. Unlike [get], the body is not
  /// buffered: the caller reads [AllowlistedStreamedResponse.body] once, and
  /// cancelling that subscription aborts the transfer.
  ///
  /// A redirect response is drained before the next hop is requested, and a
  /// final non-2xx response is drained before [HttpStatusException] is thrown,
  /// so no connection is left with unread data.
  ///
  /// Throws:
  /// * [InsecureSchemeException] for a non-HTTPS URI or redirect;
  /// * [UserInfoNotAllowedException] for a URI with embedded credentials;
  /// * [DisallowedHostException] for an empty or unlisted host;
  /// * [TooManyRedirectsException] when the chain exceeds [maxRedirects];
  /// * [HttpStatusException] for a final non-2xx status;
  /// * [HttpTimeoutException] when the response headers do not arrive within
  ///   [timeout]. Reading the body is the caller's responsibility; the
  ///   downloader applies [timeout] as an idle read timeout.
  Future<AllowlistedStreamedResponse> send(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    var currentUri = uri;
    var redirects = 0;
    Map<String, String>? requestHeaders = headers;

    while (true) {
      _ensureAllowed(currentUri);
      final response = await _sendStreamed(currentUri, requestHeaders);
      final responseHeaders = _lowercaseHeaders(response.headers);

      if (!_redirectStatuses.contains(response.statusCode)) {
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await _drain(response.stream, currentUri);
          throw HttpStatusException(response.statusCode, currentUri);
        }
        return AllowlistedStreamedResponse(
          statusCode: response.statusCode,
          headers: responseHeaders,
          body: response.stream,
          finalUri: currentUri,
        );
      }

      final location = responseHeaders['location'];
      // Drain before either following or failing, so the socket is released
      // and the next hop does not share a connection with unread bytes.
      await _drain(response.stream, currentUri);

      if (location == null || location.trim().isEmpty) {
        throw HttpStatusException(response.statusCode, currentUri);
      }
      if (redirects >= maxRedirects) {
        throw TooManyRedirectsException(
          uri,
          maxRedirects: maxRedirects,
          lastUri: currentUri,
        );
      }

      final nextUri = currentUri.resolve(location.trim());
      // Validate before counting or sending: a rejected hop must not consume
      // the budget or reach the transport.
      _ensureAllowed(nextUri);

      redirects++;
      currentUri = nextUri;
      requestHeaders = _safeRedirectHeaders(headers);
    }
  }

  /// Sends a `GET` request and returns a 2xx response.
  ///
  /// [headers] are sent on the first request only; on redirect the subset in
  /// [_redirectSafeHeaders] is forwarded. The body is fully buffered.
  ///
  /// Throws:
  /// * [InsecureSchemeException] for a non-HTTPS URI or redirect;
  /// * [UserInfoNotAllowedException] for a URI with embedded credentials;
  /// * [DisallowedHostException] for an empty or unlisted host;
  /// * [TooManyRedirectsException] when the chain exceeds [maxRedirects];
  /// * [HttpStatusException] for a final non-2xx status;
  /// * [HttpTimeoutException] when a send or body read exceeds [timeout].
  Future<AllowlistedHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final response = await send(uri, headers: headers);

    final Uint8List bodyBytes;
    try {
      bodyBytes = await http.ByteStream(response.body)
          .toBytes()
          .timeout(timeout);
    } on TimeoutException {
      throw HttpTimeoutException(response.finalUri, timeout);
    }

    return AllowlistedHttpResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      bodyBytes: bodyBytes,
      finalUri: response.finalUri,
    );
  }

  /// Sends a `GET` request and decodes a 2xx body as strict UTF-8.
  Future<String> getText(Uri uri, {Map<String, String>? headers}) async {
    final response = await get(uri, headers: headers);
    return response.bodyText;
  }

  /// Sends a `GET` request and returns the 2xx body bytes.
  Future<Uint8List> getBytes(Uri uri, {Map<String, String>? headers}) async {
    final response = await get(uri, headers: headers);
    return response.bodyBytes;
  }

  /// Closes the underlying HTTP client and releases its connections.
  void close() => _inner.close();

  void _ensureAllowed(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') {
      throw InsecureSchemeException(uri);
    }
    if (uri.host.isEmpty) {
      throw DisallowedHostException(uri, host: '');
    }
    if (uri.userInfo.isNotEmpty) {
      throw UserInfoNotAllowedException(uri);
    }
    if (!_allowlist.contains(uri.host.toLowerCase())) {
      throw DisallowedHostException(uri, host: uri.host);
    }
  }

  Future<http.StreamedResponse> _sendStreamed(
    Uri uri,
    Map<String, String>? callerHeaders,
  ) async {
    final request = http.Request('GET', uri)
      ..followRedirects = false
      ..maxRedirects = 0;

    if (callerHeaders != null) {
      for (final entry in callerHeaders.entries) {
        if (_forbiddenRequestHeaders.contains(entry.key.toLowerCase())) {
          continue;
        }
        request.headers[entry.key] = entry.value;
      }
    }
    // Set these last so a caller cannot spoof the identity or ask for a
    // transfer encoding that would change the bytes we verify.
    request.headers['user-agent'] = userAgent;
    request.headers['accept-encoding'] = 'identity';

    try {
      return await _inner.send(request).timeout(timeout);
    } on TimeoutException {
      throw HttpTimeoutException(uri, timeout);
    }
  }

  /// Reads and discards a response body that will not be handed to the caller.
  ///
  /// A redirect or an error page is irrelevant to the caller, but leaving it
  /// unread keeps a connection busy. The same [timeout] applies as to a
  /// buffered body, so a stalled transfer still fails instead of hanging.
  Future<void> _drain(Stream<List<int>> body, Uri uri) async {
    try {
      await body.drain<void>().timeout(timeout);
    } on TimeoutException {
      throw HttpTimeoutException(uri, timeout);
    }
  }

  static Map<String, String> _lowercaseHeaders(Map<String, String> headers) {
    return {
      for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
    };
  }

  static Map<String, String> _safeRedirectHeaders(
    Map<String, String>? headers,
  ) {
    if (headers == null) {
      return const {};
    }
    return {
      for (final entry in headers.entries)
        if (_redirectSafeHeaders.contains(entry.key.toLowerCase()))
          entry.key: entry.value,
    };
  }

  static Set<String> _normalizeAllowlist(Set<String>? hosts) {
    final source = hosts ?? NetworkAllowlist.productionHosts;
    final normalized = <String>{};
    for (final host in source) {
      final value = host.trim().toLowerCase();
      if (value.isEmpty ||
          value.contains('/') ||
          value.contains(':') ||
          value.contains('@')) {
        throw ArgumentError.value(
          host,
          'allowlist',
          'Expected a bare host name such as "github.com".',
        );
      }
      normalized.add(value);
    }
    return Set.unmodifiable(normalized);
  }

  static Duration _validateTimeout(Duration value) {
    if (value <= Duration.zero) {
      throw ArgumentError.value(value, 'timeout', 'Must be positive.');
    }
    return value;
  }

  static String _validateUserAgent(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.contains('\n') || trimmed.contains('\r')) {
      throw ArgumentError.value(
        value,
        'userAgent',
        'Must be a non-empty single-line value.',
      );
    }
    return trimmed;
  }

  static int _validateMaxRedirects(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'maxRedirects', 'Must not be negative.');
    }
    return value;
  }
}
