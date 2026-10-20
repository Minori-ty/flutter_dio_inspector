import 'entry.dart';

/// Renders an entry as a runnable `curl` command.
///
/// Truncated bodies are exported as-is, because the full body is no longer
/// available — the alternative would be to omit the body silently, which is
/// worse: a command that quietly sends nothing looks like it worked.
String toCurlCommand(NetworkEntry entry) {
  final parts = <String>['curl'];

  final method = entry.method.toUpperCase();
  if (method != 'GET') {
    parts.add('-X $method');
  }

  for (final header in entry.requestHeaders.entries) {
    parts.add('-H ${_quote('${header.key}: ${header.value}')}');
  }

  final body = entry.requestBody;
  if (body != null &&
      body.preview.isNotEmpty &&
      body.kind != BodyKind.binary &&
      body.kind != BodyKind.stream) {
    parts.add('--data-raw ${_quote(body.preview)}');
  }

  parts.add(_quote(entry.url));

  // One line, not a backslash-continued block. The primary use of this string is
  // "copy and paste into a terminal", and a continued command breaks in Windows
  // cmd, in most HTTP clients' import boxes, and in chat messages.
  return parts.join(' ');
}

/// Whether [value] can be passed to a shell unquoted.
final RegExp _shellSafe = RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$');

/// Single-quotes [value], escaping embedded quotes the POSIX way.
///
/// Inside single quotes a shell interprets nothing, so the only character that
/// needs care is `'` itself — which is closed, escaped and reopened as `'\''`.
/// Double quotes would be wrong here: a URL or a JSON body containing `$`,
/// a backtick or `\` would be expanded.
String _quote(String value) {
  if (value.isEmpty) return "''";
  if (_shellSafe.hasMatch(value)) return value;
  return "'${value.replaceAll("'", "'\\''")}'";
}
