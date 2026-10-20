import 'serializer.dart';

/// Decides whether a request should be recorded at all.
///
/// Returning `true` skips the request: it is neither stored nor shown. Use it to
/// keep the inspector's own traffic, analytics beacons or a health-check poller
/// out of the list.
typedef NetworkIgnorePredicate = bool Function(Uri uri, String method);

/// Tuning for the store and the interceptor.
class NetworkPanelConfig {
  const NetworkPanelConfig({
    this.enabled = true,
    this.maxEntries = 200,
    this.maxBytes = 4 * 1024 * 1024,
    this.bodyLimit = 32 * 1024,
    this.redactedHeaders = defaultRedactedHeaders,
    this.ignore,
  });

  /// When false the interceptor becomes a pass-through and nothing is recorded.
  final bool enabled;

  /// Hard cap on retained entries. Oldest are dropped first.
  final int maxEntries;

  /// Cap on the bytes of body preview held in memory.
  ///
  /// This counts the *stored previews*, not the transferred payload, because
  /// that is what the inspector actually keeps alive.
  final int maxBytes;

  /// Per-body capture limit. Longer bodies keep their size but lose their tail.
  final int bodyLimit;

  /// Header names whose values are replaced with [redactedPlaceholder].
  ///
  /// Empty by default — the whole point of the panel is to show you what was
  /// actually sent, and the header that most often explains a failure is the one
  /// carrying the credentials. Pass [sensitiveHeaders] for the usual suspects,
  /// or your own set, if the panel runs where screenshots get shared.
  final Set<String> redactedHeaders;

  final NetworkIgnorePredicate? ignore;

  NetworkPanelConfig copyWith({
    bool? enabled,
    int? maxEntries,
    int? maxBytes,
    int? bodyLimit,
    Set<String>? redactedHeaders,
    NetworkIgnorePredicate? ignore,
  }) {
    return NetworkPanelConfig(
      enabled: enabled ?? this.enabled,
      maxEntries: maxEntries ?? this.maxEntries,
      maxBytes: maxBytes ?? this.maxBytes,
      bodyLimit: bodyLimit ?? this.bodyLimit,
      redactedHeaders: redactedHeaders ?? this.redactedHeaders,
      ignore: ignore ?? this.ignore,
    );
  }
}
