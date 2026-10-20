/// Monotonic, process-local entry ids.
///
/// Ids only need to be unique for the lifetime of the process — the store is a
/// ring buffer and nothing is persisted — so a counter is enough. It is
/// zero-padded so ids sort lexicographically the way they were created, which
/// makes debug output easier to read.
library;

int _sequence = 0;

/// Returns a fresh entry id. Never returns the same value twice in a process.
String nextEntryId() => 'req-${(++_sequence).toString().padLeft(6, '0')}';

/// Resets the sequence. Only for tests, so each test starts from a known state.
void debugResetEntryIds() => _sequence = 0;
