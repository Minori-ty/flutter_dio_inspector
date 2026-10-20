import 'entry.dart';

/// How many entries are newer than the [seenId] watermark.
///
/// Entries are stored newest-first, so the answer is the watermark's position in
/// the list.
///
/// Two edge cases matter:
/// - A `null` watermark means nothing has been looked at yet, so everything
///   counts.
/// - A watermark that is no longer present was evicted by the ring buffer, which
///   only ever drops the *oldest* entries — so everything still in the list is
///   newer than it.
int countUnseen(List<NetworkEntry> entries, String? seenId) {
  if (seenId == null) return entries.length;
  final index = entries.indexWhere((entry) => entry.id == seenId);
  return index < 0 ? entries.length : index;
}

const Set<String> _empty = <String>{};

/// The ids of every entry newer than the watermark — the rows a `NEW` marker
/// belongs on.
///
/// Derived from [countUnseen] on purpose: the badge count and the per-row
/// markers are two views of the same number, so they can never disagree.
Set<String> unseenIds(List<NetworkEntry> entries, String? seenId) {
  final count = countUnseen(entries, seenId);
  if (count == 0) return _empty;
  return <String>{
    for (var index = 0; index < count; index++) entries[index].id,
  };
}
