import 'dart:convert';

/// The outcome of reading a captured body as JSON.
///
/// A record rather than a nullable value, because `null` is itself valid JSON:
/// a body of `null` and a body of `not json` must be distinguishable, and a
/// `Object?` return could not tell them apart.
typedef JsonDecodeResult = ({bool ok, Object? value});

/// Reads [text] as JSON, reporting failure instead of throwing.
///
/// Only [FormatException] is caught — that is what `jsonDecode` documents for
/// malformed input. Anything else escaping would be a genuine bug worth seeing
/// rather than something to swallow.
JsonDecodeResult decodeJson(String text) {
  try {
    return (ok: true, value: jsonDecode(text));
  } on FormatException {
    return (ok: false, value: null);
  }
}

/// Whether [value] is a JSON container rather than a primitive.
bool isJsonContainer(Object? value) => value is Map || value is List;

/// The number of entries directly inside a JSON container.
int jsonChildCount(Object? value) {
  if (value is Map) return value.length;
  if (value is List) return value.length;
  return 0;
}
