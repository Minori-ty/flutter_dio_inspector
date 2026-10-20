import 'dart:collection';

import 'entry.dart';
import 'serializer.dart';

/// A bounded, newest-first list of captured entries.
///
/// Two independent limits protect the app from the inspector:
///
/// - a **count** limit ([maxEntries]), and
/// - a **byte** limit ([maxBytes]) measured over the stored body previews.
///
/// The byte limit is what makes this safe with large responses: a body is
/// truncated to a per-body limit on capture, so a single 40 MB download costs
/// only the preview budget. And if even that exceeds the whole budget, the
/// newest entry keeps its metadata (size, kind, MIME type) while its preview is
/// dropped — an inspector that evicts the very request you just made would be
/// useless, so the newest entry is never removed.
///
/// Pure Dart, no Flutter: this is the part worth unit-testing in isolation.
class NetworkEntryBuffer {
  NetworkEntryBuffer({
    this.maxEntries = 200,
    this.maxBytes = 4 * 1024 * 1024,
  })  : assert(maxEntries > 0, 'maxEntries must be positive'),
        assert(maxBytes > 0, 'maxBytes must be positive');

  int maxEntries;
  int maxBytes;

  final List<NetworkEntry> _entries = <NetworkEntry>[];
  int _byteTotal = 0;
  int _evicted = 0;

  /// Retained entries, newest first.
  ///
  /// A view rather than a copy: the list is read on every frame while the panel
  /// is open, and copying 200 entries per frame is pointless work.
  List<NetworkEntry> get entries => UnmodifiableListView<NetworkEntry>(_entries);

  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  /// Bytes of body preview currently held.
  int get byteTotal => _byteTotal;

  /// How many entries have been dropped by either limit.
  ///
  /// Surfaced in the panel header — silently losing rows would make the list
  /// look like it missed requests.
  int get evictedCount => _evicted;

  NetworkEntry? byId(String id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// Inserts [entry] at the head and applies both limits.
  void add(NetworkEntry entry) {
    _entries.insert(0, entry);
    _byteTotal += _bytesOf(entry);
    _enforceLimits();
  }

  /// Replaces the entry with the given id.
  ///
  /// Returns `false` when the entry is gone — it was evicted between the
  /// request starting and finishing, which is normal for a burst of traffic and
  /// must not be treated as an error.
  bool replace(String id, NetworkEntry entry) {
    final index = _entries.indexWhere((candidate) => candidate.id == id);
    if (index < 0) return false;
    _byteTotal -= _bytesOf(_entries[index]);
    _entries[index] = entry;
    _byteTotal += _bytesOf(entry);
    _enforceLimits();
    return true;
  }

  void clear() {
    _entries.clear();
    _byteTotal = 0;
  }

  /// The in-memory cost of an entry: its stored previews, not the transferred
  /// payload.
  int _bytesOf(NetworkEntry entry) =>
      utf8ByteLength(entry.requestBody?.preview ?? '') +
      utf8ByteLength(entry.responseBody?.preview ?? '');

  void _enforceLimits() {
    while (_entries.length > maxEntries) {
      _evictOldest();
    }
    // Always keep at least one entry: the newest is the one the developer just
    // triggered, so evicting it would defeat the point of the panel.
    while (_entries.length > 1 && _byteTotal > maxBytes) {
      _evictOldest();
    }
    if (_entries.length == 1 && _byteTotal > maxBytes) {
      _stripNewestPreview();
    }
  }

  void _evictOldest() {
    final dropped = _entries.removeLast();
    _byteTotal -= _bytesOf(dropped);
    _evicted++;
  }

  void _stripNewestPreview() {
    final only = _entries.first;
    final requestBody = only.requestBody;
    final responseBody = only.responseBody;
    final hasPreview = (requestBody != null && requestBody.preview.isNotEmpty) ||
        (responseBody != null && responseBody.preview.isNotEmpty);
    if (!hasPreview) return;

    _byteTotal -= _bytesOf(only);
    _entries[0] = only.copyWith(
      requestBody: requestBody?.withoutPreview(),
      responseBody: responseBody?.withoutPreview(),
    );
    _byteTotal += _bytesOf(_entries[0]);
  }
}
