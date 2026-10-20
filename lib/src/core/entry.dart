/// The shape of a captured body, used to decide how the detail view renders it.
enum BodyKind {
  /// No body at all.
  empty,

  /// A JSON document.
  json,

  /// Plain text — HTML, XML, a bare string.
  text,

  /// URL-encoded or multipart form data.
  form,

  /// Bytes with no text representation, e.g. an image or a protobuf.
  binary,

  /// A stream that must not be consumed by the inspector.
  stream,
}

/// A body captured at a point in time.
///
/// [preview] may be shorter than the real body: the store truncates to a byte
/// budget so one large response cannot exhaust memory. [byteLength] always
/// reports the **full** size, so the UI can say "32 KB of 2.4 MB" honestly.
class BodySnapshot {
  const BodySnapshot({
    required this.kind,
    required this.preview,
    required this.byteLength,
    this.truncated = false,
    this.mimeType,
  });

  const BodySnapshot.empty()
      : kind = BodyKind.empty,
        preview = '',
        byteLength = 0,
        truncated = false,
        mimeType = null;

  final BodyKind kind;

  /// The captured text, possibly truncated. Empty for binary and stream bodies.
  final String preview;

  /// Size of the complete body in bytes, regardless of truncation.
  final int byteLength;

  /// Whether [preview] is a prefix of a longer body.
  final bool truncated;

  final String? mimeType;

  bool get isEmpty => kind == BodyKind.empty || (preview.isEmpty && byteLength == 0);

  /// A copy with the preview dropped but the metadata kept.
  ///
  /// Used by the store's byte budget: when a single response is larger than the
  /// whole budget, keeping the size, kind and MIME type is still useful and
  /// costs nothing.
  BodySnapshot withoutPreview() => BodySnapshot(
        kind: kind,
        preview: '',
        byteLength: byteLength,
        truncated: true,
        mimeType: mimeType,
      );
}

/// Coarse outcome of a request. Drives colour and filtering in the UI.
enum NetworkState {
  pending,
  success,
  error,
  timeout,
  canceled;

  bool get isTerminal => this != NetworkState.pending;

  bool get isFailure => this == error || this == timeout || this == canceled;
}

/// The specific reason a request failed.
///
/// Deliberately a local enum rather than `DioExceptionType`: the core layer has
/// no dependency on `dio`, which keeps it testable without an HTTP stack and
/// means a dio upgrade cannot change the stored shape.
enum NetworkFailure {
  /// connect / send / receive / transform timeout.
  timeout,

  /// Cancelled through a `CancelToken`.
  canceled,

  /// A response arrived but the status was rejected by `validateStatus`.
  badResponse,

  /// TLS certificate validation failed.
  certificate,

  /// The socket failed before a response — DNS, refused, offline.
  connection,

  /// Anything else.
  unknown,
}

/// One captured request/response pair.
///
/// Immutable: every update produces a new instance. That is what makes the
/// store's "did anything change" check cheap and lets the list diff rows.
class NetworkEntry {
  const NetworkEntry({
    required this.id,
    required this.method,
    required this.url,
    this.baseUrl = '',
    required this.startedAt,
    this.requestHeaders = const {},
    this.requestBody,
    this.state = NetworkState.pending,
    this.duration,
    this.statusCode,
    this.statusMessage,
    this.responseHeaders = const {},
    this.responseBody,
    this.responseBytes,
    this.errorMessage,
    this.failureKind,
    this.failureLabel,
  });

  final String id;
  final String method;
  final String url;

  /// The `BaseOptions.baseUrl` the request was made against, kept so the list
  /// can show the path *relative* to it (see [displayPath]).
  final String baseUrl;

  final DateTime startedAt;

  final Map<String, String> requestHeaders;
  final BodySnapshot? requestBody;

  final NetworkState state;

  /// Wall-clock time from when the interceptor saw the request to when the
  /// terminal callback fired. There is no time-to-first-byte: dio does not
  /// expose it, and reporting the total under a TTFB label would be a lie.
  final Duration? duration;

  final int? statusCode;
  final String? statusMessage;
  final Map<String, String> responseHeaders;
  final BodySnapshot? responseBody;

  /// Bytes actually transferred, when dio could tell us.
  final int? responseBytes;

  final String? errorMessage;

  /// Coarse reason, used for colour and filtering.
  final NetworkFailure? failureKind;

  /// The exact cause as reported by dio — `DioExceptionType.name`, e.g.
  /// `receiveTimeout`.
  ///
  /// Kept alongside [failureKind] because the coarse enum deliberately collapses
  /// several distinct causes into one bucket, and a panel that hides the
  /// difference between "the connection timed out" and "the response timed out"
  /// is not much of a debugging tool.
  final String? failureLabel;

  /// The path and query, relative to [baseUrl], for the list row. Falls back to
  /// the raw string when the URL cannot be parsed — a malformed URL should still
  /// be visible.
  String get displayPath {
    final parsed = Uri.tryParse(url);
    if (parsed == null) return url;
    final path = _relativePath(parsed);
    return parsed.hasQuery ? '$path?${parsed.query}' : path;
  }

  /// The request path with [baseUrl]'s path prefix removed.
  ///
  /// A base URL like `https://api.example.com/v1` turns `…/v1/todo` into
  /// `/todo`, so a list of `/v1/todo`, `/v1/user` reads as `/todo`, `/user`
  /// instead of repeating the version prefix on every row. The prefix is matched
  /// on a whole segment, so `/v1` never eats into `/v1x`. When the base URL has
  /// no path, or the paths don't line up, the full path is returned unchanged.
  String _relativePath(Uri uri) {
    final base = Uri.tryParse(baseUrl);
    if (base == null) return _pathOf(uri);

    var prefix = base.path;
    if (prefix.isEmpty || prefix == '/') return _pathOf(uri);
    if (!prefix.endsWith('/')) prefix = '$prefix/';

    final path = _pathOf(uri);
    if (!path.startsWith(prefix)) return path;
    final rest = path.substring(prefix.length);
    return rest.isEmpty ? '/' : '/$rest';
  }

  static String _pathOf(Uri uri) => uri.path.isEmpty ? '/' : uri.path;

  /// The scheme and host, shown in the detail view.
  String get displayOrigin {
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.host.isEmpty) return '';
    return '${parsed.scheme}://${parsed.host}';
  }

  NetworkEntry copyWith({
    String? method,
    String? url,
    String? baseUrl,
    Map<String, String>? requestHeaders,
    BodySnapshot? requestBody,
    NetworkState? state,
    Duration? duration,
    int? statusCode,
    String? statusMessage,
    Map<String, String>? responseHeaders,
    BodySnapshot? responseBody,
    int? responseBytes,
    String? errorMessage,
    NetworkFailure? failureKind,
    String? failureLabel,
  }) {
    return NetworkEntry(
      id: id,
      method: method ?? this.method,
      url: url ?? this.url,
      baseUrl: baseUrl ?? this.baseUrl,
      startedAt: startedAt,
      requestHeaders: requestHeaders ?? this.requestHeaders,
      requestBody: requestBody ?? this.requestBody,
      state: state ?? this.state,
      duration: duration ?? this.duration,
      statusCode: statusCode ?? this.statusCode,
      statusMessage: statusMessage ?? this.statusMessage,
      responseHeaders: responseHeaders ?? this.responseHeaders,
      responseBody: responseBody ?? this.responseBody,
      responseBytes: responseBytes ?? this.responseBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      failureKind: failureKind ?? this.failureKind,
      failureLabel: failureLabel ?? this.failureLabel,
    );
  }
}
