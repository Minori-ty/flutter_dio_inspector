import 'package:flutter/foundation.dart';

import '../core/buffer.dart';
import '../core/config.dart';
import '../core/entry.dart';
import '../core/id.dart';
import '../core/serializer.dart';

/// Holds captured traffic and tells the UI when it changes.
///
/// A thin [ChangeNotifier] over [NetworkEntryBuffer] — all the eviction policy
/// lives in the buffer, which stays pure Dart and is unit-tested on its own.
///
/// Create one per app (or per `Dio` instance you want to watch) and hand the
/// same instance to both [DioNetworkPanelInterceptor] and the panel widget.
class NetworkStore extends ChangeNotifier {
  NetworkStore({NetworkPanelConfig config = const NetworkPanelConfig()})
      : _config = config,
        _buffer = NetworkEntryBuffer(
          maxEntries: config.maxEntries,
          maxBytes: config.maxBytes,
        );

  NetworkPanelConfig _config;
  final NetworkEntryBuffer _buffer;

  bool _disposed = false;

  NetworkPanelConfig get config => _config;

  /// Updates the configuration. Entry and byte caps take effect immediately.
  set config(NetworkPanelConfig value) {
    _config = value;
    _buffer
      ..maxEntries = value.maxEntries
      ..maxBytes = value.maxBytes;
    _notify();
  }

  /// Captured entries, newest first.
  List<NetworkEntry> get entries => _buffer.entries;

  /// How many entries have been dropped by the count or byte limit.
  int get evictedCount => _buffer.evictedCount;

  /// Bytes of body preview currently held.
  int get byteTotal => _buffer.byteTotal;

  NetworkEntry? byId(String id) => _buffer.byId(id);

  /// Records the start of a request and returns its entry id.
  ///
  /// [headers] are redacted here rather than by the caller, so configuring
  /// redaction is enough — no call site can store a value it should have hidden
  /// by forgetting to. Nothing is redacted unless
  /// `config.redactedHeaders` says so.
  String begin({
    required String method,
    required String url,
    String baseUrl = '',
    required Map<String, String> headers,
    BodySnapshot? body,
    DateTime? startedAt,
  }) {
    final entry = NetworkEntry(
      id: nextEntryId(),
      method: method.toUpperCase(),
      url: url,
      baseUrl: baseUrl,
      startedAt: startedAt ?? DateTime.now(),
      requestHeaders: redactHeaders(headers, _config.redactedHeaders),
      requestBody: body,
    );
    _buffer.add(entry);
    _notify();
    return entry.id;
  }

  /// Applies [update] to the entry with [id].
  ///
  /// Does nothing when the entry is already gone: a burst of traffic can evict
  /// an in-flight request before it finishes, and that is not an error.
  void patch(String id, NetworkEntry Function(NetworkEntry current) update) {
    final current = _buffer.byId(id);
    if (current == null) return;
    if (_buffer.replace(id, update(current))) {
      _notify();
    }
  }

  void clear() {
    _buffer.clear();
    _notify();
  }

  /// Notifies listeners straight away.
  ///
  /// An earlier version deferred this to a microtask to "coalesce" a burst of
  /// updates. That was a mistake: Flutter already collapses multiple
  /// `markNeedsBuild` calls within a frame into a single rebuild, so the extra hop
  /// bought nothing and cost a frame of latency — a notification raised from a
  /// microtask only reaches the screen on the *following* frame, because the frame
  /// that is already in flight has passed the point where it collects dirty
  /// elements.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
