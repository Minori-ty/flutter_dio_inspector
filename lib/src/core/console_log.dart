/// Renders a finished request as a console block for `debugPrint`.
///
/// One summary line — method, path, duration, status — followed by an indented
/// `req` / `res` line for each captured body. Method and status colours mirror
/// the panel's, so a colour means the same thing in both places; pass
/// `color: false` for a plain-text form a test can assert on.
library;

import 'entry.dart';
import 'format.dart';

// Method colours, shared with `NetworkPanelTheme.methodColor` so the terminal
// and the overlay agree.
const int _methodGet = 0x0A84FF;
const int _methodPost = 0x8B5CF6;
const int _methodPut = 0xF97316;
const int _methodPatch = 0xA16207;
const int _methodDelete = 0xEF4444;
const int _methodMisc = 0x0D9488;
const int _methodUnknown = 0x6B7280;

// Status colours — the dark-theme variants, readable on a typical terminal.
const int _statusSuccess = 0x30D158;
const int _statusRedirect = 0x0A84FF;
const int _statusWarning = 0xFFD60A;
const int _statusDanger = 0xFF453A;
const int _statusNeutral = 0x6B7280;

/// Builds the console text for one finished request.
///
/// [entry] should be a terminal entry (success, error, timeout or canceled) —
/// the interceptor only logs once the request has completed, and a pending
/// entry has no duration or status worth printing yet.
String formatConsoleLog(NetworkEntry entry, {bool color = true}) {
  final method = entry.method;
  final status = _statusText(entry);

  final buffer = StringBuffer()
    ..write(_paint(method, _methodColor(method), color))
    ..write(' ')
    ..write(entry.displayPath)
    ..write(' ')
    ..write(formatDuration(entry.duration))
    ..write(' ')
    ..write(_paint(status, _statusColor(entry), color));

  final request = entry.requestBody?.preview;
  if (request != null && request.isNotEmpty) {
    buffer
      ..write('\n  req  ')
      ..write(request);
  }
  final response = entry.responseBody?.preview;
  if (response != null && response.isNotEmpty) {
    buffer
      ..write('\n  res  ')
      ..write(response);
  }

  return buffer.toString();
}

/// The status slot: the code when there is one, otherwise the failure reason —
/// a timeout has no status but should still say why it is red.
String _statusText(NetworkEntry entry) {
  final status = entry.statusCode;
  if (status != null) return '$status';
  return entry.errorMessage ?? entry.failureLabel ?? entry.state.name;
}

int _methodColor(String method) {
  switch (method.toUpperCase()) {
    case 'GET':
      return _methodGet;
    case 'POST':
      return _methodPost;
    case 'PUT':
      return _methodPut;
    case 'PATCH':
      return _methodPatch;
    case 'DELETE':
      return _methodDelete;
    case 'HEAD':
    case 'OPTIONS':
      return _methodMisc;
    default:
      return _methodUnknown;
  }
}

int _statusColor(NetworkEntry entry) {
  final status = entry.statusCode;
  if (status != null) {
    if (status < 300) return _statusSuccess;
    if (status < 400) return _statusRedirect;
    if (status < 500) return _statusWarning;
    return _statusDanger;
  }
  switch (entry.state) {
    case NetworkState.timeout:
      return _statusWarning;
    case NetworkState.error:
    case NetworkState.canceled:
      return _statusDanger;
    case NetworkState.pending:
    case NetworkState.success:
      return _statusNeutral;
  }
}

/// Wraps [text] in a 24-bit foreground colour when [color] is true.
String _paint(String text, int rgb, bool color) {
  if (!color) return text;
  final r = (rgb >> 16) & 0xFF;
  final g = (rgb >> 8) & 0xFF;
  final b = rgb & 0xFF;
  return '\x1b[38;2;$r;$g;${b}m$text\x1b[0m';
}
