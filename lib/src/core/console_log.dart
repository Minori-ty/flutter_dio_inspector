/// Renders a finished request as a coloured console block for `debugPrint`.
///
/// The whole block — a box drawn around the summary line and the captured
/// bodies — is tinted in the method's colour, so in a busy terminal one request
/// reads as one solid rectangle rather than a single coloured token. JSON bodies
/// are pretty-printed with indentation. Pass `color: false` for the plain-text
/// form a test can assert on.
library;

import 'dart:convert';

import 'entry.dart';
import 'format.dart';
import 'json_preview.dart';

// Method colours, shared with `NetworkPanelTheme.methodColor` so the terminal
// and the overlay agree.
const int _methodGet = 0x0A84FF;
const int _methodPost = 0x8B5CF6;
const int _methodPut = 0xF97316;
const int _methodPatch = 0xA16207;
const int _methodDelete = 0xEF4444;
const int _methodMisc = 0x0D9488;
const int _methodUnknown = 0x6B7280;

const String _topLeft = '┌';
const String _topRight = '┐';
const String _bottomLeft = '└';
const String _bottomRight = '┘';
const String _horizontal = '─';
const String _vertical = '│';

/// Builds the console text for one finished request.
///
/// [entry] should be a terminal entry (success, error, timeout or canceled) —
/// the interceptor only logs once the request has completed, and a pending
/// entry has no duration or status worth printing yet.
String formatConsoleLog(NetworkEntry entry, {bool color = true}) {
  final lines = _contentLines(entry);

  var width = 0;
  for (final line in lines) {
    final w = _displayWidth(line);
    if (w > width) width = w;
  }

  final box = StringBuffer()
    ..writeln(_topLeft + _repeat(_horizontal, width + 2) + _topRight);
  for (final line in lines) {
    box
      ..write(_vertical)
      ..write(' ')
      ..write(line)
      ..write(_spaces(width - _displayWidth(line)))
      ..write(' ')
      ..writeln(_vertical);
  }
  box.write(_bottomLeft + _repeat(_horizontal, width + 2) + _bottomRight);

  return _paint(box.toString(), _methodColor(entry.method), color);
}

/// The box's rows, in order, before any border or colour is applied. Widths are
/// measured from these so the right border aligns even with CJK text.
List<String> _contentLines(NetworkEntry entry) {
  final lines = <String>[
    '${entry.method} ${entry.displayPath} '
        '${formatDuration(entry.duration)} ${_statusText(entry)}',
  ];

  final request = entry.requestBody;
  if (request != null && request.preview.isNotEmpty) {
    lines
      ..add('')
      ..add('req')
      ..addAll(_indent(_wrapLines(_bodyLines(request))));
  }
  final response = entry.responseBody;
  if (response != null && response.preview.isNotEmpty) {
    lines
      ..add('')
      ..add('res')
      ..addAll(_indent(_wrapLines(_bodyLines(response))));
  }
  final error = entry.errorMessage;
  if (error != null && error.isNotEmpty) {
    lines
      ..add('')
      ..add('error')
      ..addAll(_indent(_wrapLines(error.split('\n'))));
  }

  return lines;
}

/// One line per physical row, pretty-printed when the body is JSON.
List<String> _bodyLines(BodySnapshot body) {
  final text = body.kind == BodyKind.json ? _prettyJson(body.preview) : body.preview;
  return text.split('\n');
}

/// Re-encodes a JSON preview with indentation, falling back to the raw text when
/// it does not parse — a preview truncated at the capture limit is often not
/// valid JSON.
String _prettyJson(String text) {
  final result = decodeJson(text);
  final value = result.value;
  if (!result.ok || value is! Map && value is! List) return text;
  return const JsonEncoder.withIndent('  ').convert(value);
}

List<String> _indent(List<String> lines) =>
    <String>[for (final line in lines) '  $line'];

/// Section lines are wrapped to this many terminal columns so a long error
/// message or body widens the box into wrap instead of running off the right
/// edge of a narrow terminal. `dart:io` is not imported (the package runs on
/// web), so the real terminal width is unknown and this fixed cap is the
/// compromise.
const int _maxLineWidth = 100;

/// Wraps each already-split line to [_maxLineWidth].
List<String> _wrapLines(List<String> lines) {
  final result = <String>[];
  for (final line in lines) {
    result.addAll(_wrap(line, _maxLineWidth));
  }
  return result;
}

/// Breaks a single line at the first rune that would push it past [maxWidth]
/// display columns, so the box never exceeds a terminal that is exactly
/// [maxWidth] wide. Wide (CJK/emoji) runes count two columns.
List<String> _wrap(String line, int maxWidth) {
  if (_displayWidth(line) <= maxWidth) return <String>[line];
  final result = <String>[];
  var current = '';
  var width = 0;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final w = _isWide(rune) ? 2 : 1;
    if (current.isNotEmpty && width + w > maxWidth) {
      result.add(current);
      current = '';
      width = 0;
    }
    current += ch;
    width += w;
  }
  if (current.isNotEmpty) result.add(current);
  return result;
}

/// The status slot: the code when there is one, otherwise dio's exact cause —
/// kept short so the summary line stays on one line. The human-readable error
/// message gets its own wrapped section instead (see [_contentLines]).
String _statusText(NetworkEntry entry) {
  final status = entry.statusCode;
  if (status != null) return '$status';
  return entry.failureLabel ?? entry.state.name;
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

/// Wraps [text] in a 24-bit foreground colour when [color] is true.
String _paint(String text, int rgb, bool color) {
  if (!color) return text;
  final r = (rgb >> 16) & 0xFF;
  final g = (rgb >> 8) & 0xFF;
  final b = rgb & 0xFF;
  return '\x1b[38;2;$r;$g;${b}m$text\x1b[0m';
}

/// Terminal columns [text] occupies: East-Asian wide characters count two, so
/// the box's right border stays aligned when a body holds CJK text.
int _displayWidth(String text) {
  var width = 0;
  for (final rune in text.runes) {
    width += _isWide(rune) ? 2 : 1;
  }
  return width;
}

bool _isWide(int rune) {
  return (rune >= 0x1100 && rune <= 0x115F) || // Hangul Jamo
      (rune >= 0x2E80 && rune <= 0xA4CF) || // CJK radicals .. Yi
      (rune >= 0xAC00 && rune <= 0xD7A3) || // Hangul syllables
      (rune >= 0xF900 && rune <= 0xFAFF) || // CJK compatibility ideographs
      (rune >= 0xFE30 && rune <= 0xFE4F) || // CJK compatibility forms
      (rune >= 0xFF00 && rune <= 0xFF60) || // fullwidth forms
      (rune >= 0xFFE0 && rune <= 0xFFE6) || // fullwidth signs
      (rune >= 0x20000 && rune <= 0x3FFFD) || // CJK extension B+
      (rune >= 0x1F300 && rune <= 0x1FAFF); // emoji & pictographs
}

String _spaces(int count) => ''.padRight(count);

String _repeat(String unit, int count) {
  final buffer = StringBuffer();
  for (var i = 0; i < count; i++) {
    buffer.write(unit);
  }
  return buffer.toString();
}
