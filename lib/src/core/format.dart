/// Human-readable byte sizes: `812 B`, `4.2 KB`, `1.1 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}

/// Compact durations, no space before the unit: `140ms`, `1.2s`, `2m 03s`.
///
/// A space reads as a separate token when the value sits next to a status code
/// in a narrow column.
String formatDuration(Duration? duration) {
  if (duration == null) return '—';
  final micros = duration.inMicroseconds;
  if (micros < 1000) return '$microsµs';
  final millis = duration.inMilliseconds;
  if (millis < 1000) return '${millis}ms';
  final seconds = micros / 1000000;
  if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
  final minutes = duration.inMinutes;
  final restSeconds = duration.inSeconds - minutes * 60;
  return '${minutes}m ${restSeconds.toString().padLeft(2, '0')}s';
}

/// `HH:mm:ss.SSS` — enough precision to line a request up with a log line.
String formatClock(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}'
      '.${time.millisecond.toString().padLeft(3, '0')}';
}
