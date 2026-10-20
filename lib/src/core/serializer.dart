import 'dart:convert';

import 'entry.dart';

/// The placeholder written in place of a redacted header value.
const String redactedPlaceholder = '••••••';

/// Redacted by default: nothing.
///
/// The panel exists to answer "why is this request wrong?", and the answer is
/// very often the `Authorization` header itself — a missing `Bearer ` prefix, a
/// token from the wrong environment, one that expired an hour ago. Masking it
/// turns the field you opened the panel to read into `••••••`, which is a
/// debugging tool refusing to debug.
///
/// Redaction is still available, and still applied in the store rather than at
/// the call site: set `NetworkPanelConfig.redactedHeaders` to [sensitiveHeaders]
/// (or any set of names) when the panel runs somewhere screenshots get shared.
const Set<String> defaultRedactedHeaders = <String>{};

/// The header names worth hiding *when* you ask for redaction.
///
/// Matched case-insensitively, because HTTP header names are. Nothing here is
/// applied unless it is passed to `NetworkPanelConfig.redactedHeaders` — see
/// [defaultRedactedHeaders] for why.
const Set<String> sensitiveHeaders = {
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
  'x-auth-token',
};

/// Number of bytes [value] occupies when encoded as UTF-8.
///
/// Counted by rune rather than by `String.length`, which is UTF-16 code units —
/// a single emoji is 2 code units but 4 bytes.
int utf8ByteLength(String value) {
  var total = 0;
  for (final rune in value.runes) {
    total += _utf8SizeOfRune(rune);
  }
  return total;
}

int _utf8SizeOfRune(int rune) {
  if (rune < 0x80) return 1;
  if (rune < 0x800) return 2;
  if (rune < 0x10000) return 3;
  return 4;
}

/// The longest prefix of [value] that fits in [limit] bytes.
///
/// Never splits a code point: cutting a 4-byte emoji in half would produce an
/// invalid string that renders as a replacement character.
String truncateToBytes(String value, int limit) {
  if (limit <= 0) return '';
  if (utf8ByteLength(value) <= limit) return value;

  final buffer = StringBuffer();
  var used = 0;
  for (final rune in value.runes) {
    final size = _utf8SizeOfRune(rune);
    if (used + size > limit) break;
    buffer.writeCharCode(rune);
    used += size;
  }
  return buffer.toString();
}

/// Case-insensitive lookup, returning `null` when the header is absent.
String? headerValue(Map<String, String> headers, String name) {
  final target = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == target) return entry.value;
  }
  return null;
}

/// A copy of [headers] with sensitive values replaced.
///
/// The *name* is kept: knowing that a request carried an `Authorization` header
/// is useful, knowing its value is not worth the risk of it ending up in a
/// screenshot or a bug report.
Map<String, String> redactHeaders(
  Map<String, String> headers,
  Set<String> redacted,
) {
  if (redacted.isEmpty || headers.isEmpty) return Map<String, String>.of(headers);
  final lower = redacted.map((name) => name.toLowerCase()).toSet();
  return <String, String>{
    for (final entry in headers.entries)
      entry.key: lower.contains(entry.key.toLowerCase())
          ? redactedPlaceholder
          : entry.value,
  };
}

/// Guesses how a body should be rendered, preferring the declared MIME type and
/// falling back to sniffing the content.
BodyKind detectBodyKind(String preview, String? mimeType) {
  if (preview.isEmpty) return BodyKind.empty;

  final mime = mimeType?.toLowerCase();
  if (mime != null) {
    if (mime.contains('json')) return BodyKind.json;
    if (mime.contains('x-www-form-urlencoded') || mime.contains('multipart/form-data')) {
      return BodyKind.form;
    }
    if (mime.startsWith('text/') || mime.contains('xml') || mime.contains('javascript')) {
      return BodyKind.text;
    }
    if (mime.startsWith('image/') ||
        mime.startsWith('audio/') ||
        mime.startsWith('video/') ||
        mime.contains('octet-stream') ||
        mime.contains('protobuf')) {
      return BodyKind.binary;
    }
  }

  final trimmed = preview.trimLeft();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) return BodyKind.json;

  // A body with no MIME hint: printable text is treated as text, anything with
  // control characters as binary.
  for (final rune in preview.runes) {
    if (rune == 0x09 || rune == 0x0A || rune == 0x0D) continue;
    if (rune < 0x20) return BodyKind.binary;
  }
  return BodyKind.text;
}

/// A text body, truncated to [byteLimit].
BodySnapshot textSnapshot(
  String text, {
  required int byteLimit,
  String? mimeType,
}) {
  if (text.isEmpty) return const BodySnapshot.empty();
  final truncated = truncateToBytes(text, byteLimit);
  return BodySnapshot(
    kind: detectBodyKind(truncated, mimeType),
    preview: truncated,
    byteLength: utf8ByteLength(text),
    truncated: truncated.length != text.length,
    mimeType: mimeType,
  );
}

/// A body that exists but has no text form. Only its size is recorded.
BodySnapshot binarySnapshot(int byteLength, {String? mimeType}) => BodySnapshot(
      kind: BodyKind.binary,
      preview: '',
      byteLength: byteLength,
      mimeType: mimeType,
    );

/// A body that was handed to us as a stream.
///
/// Nothing is read: consuming the stream here would break the real request.
BodySnapshot streamSnapshot({String? mimeType, int? byteLength}) => BodySnapshot(
      kind: BodyKind.stream,
      preview: '',
      byteLength: byteLength ?? 0,
      mimeType: mimeType,
    );

/// Snapshots an arbitrary request or response payload.
///
/// Returns `null` for "no body" so the UI can distinguish it from an empty one.
BodySnapshot? snapshotData(
  Object? data, {
  required int byteLimit,
  String? mimeType,
}) {
  if (data == null) return null;

  if (data is String) {
    return textSnapshot(data, byteLimit: byteLimit, mimeType: mimeType);
  }

  if (data is List<int>) {
    return binarySnapshot(data.length, mimeType: mimeType);
  }

  // dio hands back a Map or a List for JSON payloads that were already decoded
  // by a transformer, so re-encode it to show something readable.
  if (data is Map || data is List) {
    try {
      final encoded = jsonEncode(data);
      return textSnapshot(
        encoded,
        byteLimit: byteLimit,
        mimeType: mimeType ?? 'application/json',
      );
    } on JsonUnsupportedObjectError {
      return textSnapshot(
        data.toString(),
        byteLimit: byteLimit,
        mimeType: mimeType,
      );
    }
  }

  return textSnapshot(data.toString(), byteLimit: byteLimit, mimeType: mimeType);
}
