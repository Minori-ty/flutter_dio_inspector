import 'package:flutter_dio_inspector/flutter_dio_inspector.dart';
import 'package:flutter_dio_inspector/src/core/serializer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Terminal columns of [s], mirroring the wide-character ruler in the console
/// logger so the alignment test measures with the same one.
int _cols(String s) {
  var width = 0;
  for (final rune in s.runes) {
    width += _wide(rune) ? 2 : 1;
  }
  return width;
}

bool _wide(int rune) =>
    (rune >= 0x1100 && rune <= 0x115F) ||
    (rune >= 0x2E80 && rune <= 0xA4CF) ||
    (rune >= 0xAC00 && rune <= 0xD7A3) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0xFE30 && rune <= 0xFE4F) ||
    (rune >= 0xFF00 && rune <= 0xFF60) ||
    (rune >= 0xFFE0 && rune <= 0xFFE6) ||
    (rune >= 0x20000 && rune <= 0x3FFFD) ||
    (rune >= 0x1F300 && rune <= 0x1FAFF);

void main() {
  group('utf8ByteLength', () {
    test('counts bytes, not UTF-16 code units', () {
      expect(utf8ByteLength('abc'), 3);
      expect(utf8ByteLength('中文'), 6);
      expect(utf8ByteLength('😀'), 4);
      // The point of the whole function: String.length would say 2 here.
      expect('😀'.length, 2);
    });

    test('agrees with dart:convert for a mixed string', () {
      const value = 'a中😀\n';
      expect(utf8ByteLength(value), value.runes.fold<int>(0, (total, rune) {
        if (rune < 0x80) return total + 1;
        if (rune < 0x800) return total + 2;
        if (rune < 0x10000) return total + 3;
        return total + 4;
      }));
    });
  });

  group('truncateToBytes', () {
    test('never splits a code point', () {
      // An emoji is 4 bytes; a 3-byte budget cannot hold any part of it.
      expect(truncateToBytes('😀', 3), '');
      expect(truncateToBytes('😀', 4), '😀');
      expect(truncateToBytes('a😀', 4), 'a');
      expect(truncateToBytes('a😀', 5), 'a😀');
    });

    test('stops on a byte boundary, not a character boundary', () {
      // '中文' is 6 bytes, so a 4-byte budget fits exactly one character.
      expect(truncateToBytes('中文', 4), '中');
      expect(utf8ByteLength(truncateToBytes('中文abc', 4)), 3);
    });

    test('returns the input untouched when it already fits', () {
      expect(truncateToBytes('abc', 10), 'abc');
    });

    test('a zero or negative budget yields nothing', () {
      expect(truncateToBytes('abc', 0), '');
      expect(truncateToBytes('abc', -5), '');
    });
  });

  group('redactHeaders', () {
    test('nothing is redacted by default', () {
      final result = redactHeaders(
        {'Authorization': 'Bearer super-secret', 'Cookie': 'session=1'},
        defaultRedactedHeaders,
      );

      // The header you open a network panel to read is usually this one.
      expect(result['Authorization'], 'Bearer super-secret');
      expect(result['Cookie'], 'session=1');
    });

    test('replaces sensitive values and keeps the header name', () {
      final result = redactHeaders(
        {'Authorization': 'Bearer super-secret', 'X-Trace': 'abc'},
        sensitiveHeaders,
      );
      expect(result['Authorization'], redactedPlaceholder);
      expect(result['X-Trace'], 'abc');
    });

    test('matches case-insensitively, because HTTP header names are', () {
      final result = redactHeaders(
        {'authorization': 'Bearer x', 'COOKIE': 'session=1'},
        sensitiveHeaders,
      );
      expect(result['authorization'], redactedPlaceholder);
      expect(result['COOKIE'], redactedPlaceholder);
    });

    test('does not mutate the input map', () {
      final original = {'Authorization': 'Bearer x'};
      redactHeaders(original, sensitiveHeaders);
      expect(original['Authorization'], 'Bearer x');
    });

    test('returns a copy even when nothing is redacted', () {
      final original = {'X-Trace': 'abc'};
      final result = redactHeaders(original, defaultRedactedHeaders);
      expect(result, isNot(same(original)));
      expect(result['X-Trace'], 'abc');
    });
  });

  group('snapshotData', () {
    test('null means no body at all, not an empty one', () {
      expect(snapshotData(null, byteLimit: 1024), isNull);
    });

    test('classifies a Map as JSON', () {
      final snapshot = snapshotData({'a': 1}, byteLimit: 1024)!;
      expect(snapshot.kind, BodyKind.json);
      expect(snapshot.preview, '{"a":1}');
    });

    test('classifies a List of bytes as binary, keeping only the size', () {
      final snapshot = snapshotData(<int>[1, 2, 3, 4], byteLimit: 1024)!;
      expect(snapshot.kind, BodyKind.binary);
      expect(snapshot.byteLength, 4);
      expect(snapshot.preview, isEmpty);
    });

    test('a truncated body keeps its full size', () {
      final snapshot = snapshotData('x' * 100, byteLimit: 10)!;
      expect(snapshot.preview.length, 10);
      expect(snapshot.byteLength, 100);
      expect(snapshot.truncated, isTrue);
    });

    test('uses the MIME type to classify when it disagrees with the content', () {
      final snapshot = snapshotData(
        'not really json',
        byteLimit: 1024,
        mimeType: 'application/json',
      )!;
      expect(snapshot.kind, BodyKind.json);
    });
  });

  group('NetworkEntryBuffer', () {
    NetworkEntry makeEntry(String id, {String body = ''}) => NetworkEntry(
          id: id,
          method: 'GET',
          url: 'https://api.test/$id',
          startedAt: DateTime(2026, 10, 16),
          responseBody: BodySnapshot(
            kind: BodyKind.text,
            preview: body,
            byteLength: body.length,
          ),
        );

    test('keeps entries newest first', () {
      final buffer = NetworkEntryBuffer();
      buffer.add(makeEntry('a'));
      buffer.add(makeEntry('b'));
      expect(buffer.entries.map((entry) => entry.id), <String>['b', 'a']);
    });

    test('exposes an unmodifiable view', () {
      final buffer = NetworkEntryBuffer()..add(makeEntry('a'));
      expect(() => buffer.entries.add(makeEntry('b')), throwsUnsupportedError);
    });

    test('drops the oldest when the count limit is reached', () {
      final buffer = NetworkEntryBuffer(maxEntries: 3, maxBytes: 1 << 20);
      for (final id in <String>['a', 'b', 'c', 'd']) {
        buffer.add(makeEntry(id));
      }
      expect(buffer.entries.map((entry) => entry.id), <String>['d', 'c', 'b']);
      expect(buffer.evictedCount, 1);
    });

    test('drops the oldest when the byte budget is exceeded', () {
      final buffer = NetworkEntryBuffer(maxEntries: 100, maxBytes: 10);
      buffer.add(makeEntry('a', body: 'x' * 6));
      buffer.add(makeEntry('b', body: 'y' * 6));

      expect(buffer.entries.map((entry) => entry.id), <String>['b']);
      expect(buffer.evictedCount, 1);
      expect(buffer.byteTotal, 6);
    });

    test('keeps the newest entry and strips its preview when one body alone '
        'exceeds the whole budget', () {
      final buffer = NetworkEntryBuffer(maxEntries: 100, maxBytes: 4);
      buffer.add(makeEntry('a', body: 'x' * 50));

      expect(buffer.length, 1);
      final only = buffer.entries.single;
      expect(only.id, 'a');
      expect(only.responseBody!.preview, isEmpty);
      // The metadata is the point of the degradation: size survives.
      expect(only.responseBody!.byteLength, 50);
      expect(only.responseBody!.truncated, isTrue);
      expect(buffer.byteTotal, 0);
    });

    test('replace reports failure for an entry that was already evicted', () {
      final buffer = NetworkEntryBuffer(maxEntries: 1, maxBytes: 1 << 20);
      buffer.add(makeEntry('a'));
      buffer.add(makeEntry('b'));
      expect(buffer.replace('a', makeEntry('a')), isFalse);
      expect(buffer.replace('b', makeEntry('b')), isTrue);
    });

    test('replace accounts for the byte delta', () {
      final buffer = NetworkEntryBuffer(maxEntries: 10, maxBytes: 1 << 20);
      buffer.add(makeEntry('a', body: 'x' * 10));
      expect(buffer.byteTotal, 10);

      buffer.replace('a', makeEntry('a', body: 'x' * 3));
      expect(buffer.byteTotal, 3);
    });

    test('clear empties everything including the byte total', () {
      final buffer = NetworkEntryBuffer()
        ..add(makeEntry('a', body: 'xxxx'))
        ..clear();
      expect(buffer.isEmpty, isTrue);
      expect(buffer.byteTotal, 0);
    });
  });

  group('unseen tracking', () {
    List<NetworkEntry> entries(int count) => <NetworkEntry>[
          for (var index = 0; index < count; index++)
            NetworkEntry(
              id: 'req-$index',
              method: 'GET',
              url: 'https://api.test/$index',
              startedAt: DateTime(2026, 10, 16),
            ),
        ];

    test('a null watermark counts everything', () {
      expect(countUnseen(entries(3), null), 3);
    });

    test('the watermark position is the count', () {
      expect(countUnseen(entries(5), 'req-2'), 2);
    });

    test('an evicted watermark counts everything still in the list', () {
      // Eviction only ever drops the oldest, so a missing watermark means every
      // remaining entry is newer than it.
      expect(countUnseen(entries(4), 'req-gone'), 4);
    });

    test('the marker set and the badge count can never disagree', () {
      final list = entries(6);
      final candidates = <String?>[
        null,
        'req-gone',
        ...list.map((entry) => entry.id),
      ];

      for (final watermark in candidates) {
        final ids = unseenIds(list, watermark);
        expect(
          ids.length,
          countUnseen(list, watermark),
          reason: 'markers and count disagree for watermark $watermark',
        );
      }
    });

    test('an empty list has nothing unseen', () {
      expect(countUnseen(<NetworkEntry>[], null), 0);
      expect(unseenIds(<NetworkEntry>[], null), isEmpty);
    });
  });

  group('displayPath', () {
    NetworkEntry entry(String url, {String baseUrl = ''}) => NetworkEntry(
          id: 'req-1',
          method: 'GET',
          url: url,
          baseUrl: baseUrl,
          startedAt: DateTime(2026, 10, 16),
        );

    test('strips the baseUrl path prefix from the row path', () {
      expect(
        entry('https://api.test/v1/todo', baseUrl: 'https://api.test/v1')
            .displayPath,
        '/todo',
      );
      expect(
        entry('https://api.test/v1/todo', baseUrl: 'https://api.test/v1/')
            .displayPath,
        '/todo',
      );
    });

    test('keeps the full path when the baseUrl has no path', () {
      expect(
        entry('https://api.test/todo', baseUrl: 'https://api.test').displayPath,
        '/todo',
      );
      expect(entry('https://api.test/todo').displayPath, '/todo');
    });

    test('does not over-strip a segment that merely shares a prefix', () {
      expect(
        entry('https://api.test/v1x/todo', baseUrl: 'https://api.test/v1')
            .displayPath,
        '/v1x/todo',
      );
    });

    test('preserves the query string', () {
      expect(
        entry(
          'https://api.test/v1/todo?limit=10',
          baseUrl: 'https://api.test/v1',
        ).displayPath,
        '/todo?limit=10',
      );
    });
  });

  group('formatConsoleLog', () {
    NetworkEntry entry({
      String method = 'GET',
      String url = 'https://api.test/v1/todo',
      String baseUrl = 'https://api.test/v1',
      int? status = 200,
      Duration? duration = const Duration(milliseconds: 140),
      String? requestBody,
      String? responseBody,
      NetworkState state = NetworkState.success,
      String? errorMessage,
    }) =>
        NetworkEntry(
          id: 'req-1',
          method: method,
          url: url,
          baseUrl: baseUrl,
          startedAt: DateTime(2026, 10, 16),
          state: state,
          statusCode: status,
          duration: duration,
          requestBody: requestBody == null
              ? null
              : BodySnapshot(
                  kind: BodyKind.json,
                  preview: requestBody,
                  byteLength: requestBody.length,
                ),
          responseBody: responseBody == null
              ? null
              : BodySnapshot(
                  kind: BodyKind.json,
                  preview: responseBody,
                  byteLength: responseBody.length,
                ),
          errorMessage: errorMessage,
        );

    test('draws a box around the summary line', () {
      final out = formatConsoleLog(entry(), color: false);
      expect(out, startsWith('┌'));
      expect(out, endsWith('┘'));
      expect(out, contains('│ GET /todo 140ms 200 │'));
    });

    test('pretty-prints JSON bodies with indentation', () {
      final out = formatConsoleLog(
        entry(requestBody: '{"a":1}', responseBody: '{"b":2}'),
        color: false,
      );
      expect(out, contains('req'));
      expect(out, contains('res'));
      // Compact JSON is re-encoded with indentation and a space after ':'.
      expect(out, isNot(contains('{"a":1}')));
      expect(out, contains('"a": 1'));
    });

    test('leaves a text body unformatted', () {
      final e = NetworkEntry(
        id: 'req-1',
        method: 'GET',
        url: 'https://api.test/todo',
        startedAt: DateTime(2026, 10, 16),
        state: NetworkState.success,
        statusCode: 200,
        duration: const Duration(milliseconds: 140),
        responseBody: BodySnapshot(
          kind: BodyKind.text,
          preview: '<html></html>',
          byteLength: 13,
        ),
      );
      expect(formatConsoleLog(e, color: false), contains('<html></html>'));
    });

    test('keeps the summary short and puts the error message in its own section', () {
      final out = formatConsoleLog(
        entry(status: null, state: NetworkState.error, errorMessage: 'Connection failed'),
        color: false,
      );
      // The failure reason fills the status slot, not the whole message — a long
      // message must not widen the summary line past a narrow terminal.
      expect(out, contains('GET /todo 140ms error'));
      expect(out, contains('error'));
      expect(out, contains('Connection failed'));
    });

    test('wraps a long error message instead of widening the box', () {
      final out = formatConsoleLog(
        entry(
          status: null,
          state: NetworkState.error,
          errorMessage: ''.padRight(250, 'x'),
        ),
        color: false,
      );
      final rows =
          out.split('\n').where((line) => line.startsWith('│')).toList();
      expect(rows, isNotEmpty);
      // Body lines wrap to 100 columns, then gain the two-space indent, then the
      // '│ ' / ' │' padding — 106 interior columns, not the 250 of the message.
      final widest = rows.map(_cols).reduce((a, b) => a > b ? a : b);
      expect(widest, lessThanOrEqualTo(106));
    });

    test('keeps the right border aligned with CJK text', () {
      final out = formatConsoleLog(
        entry(responseBody: '{"msg":"你好"}'),
        color: false,
      );
      expect(out, contains('你好'));
      final rows =
          out.split('\n').where((line) => line.startsWith('│')).toList();
      expect(rows, isNotEmpty);
      expect(rows.map(_cols).toSet(), hasLength(1));
    });

    test('wraps the whole block in ANSI colour when enabled', () {
      final out = formatConsoleLog(entry(), color: true);
      expect(out, startsWith('\x1b[38;2;'));
      expect(out, endsWith('\x1b[0m'));
      expect(out, contains('┌'));
    });
  });

  group('toCurlCommand', () {
    NetworkEntry entry({
      String method = 'GET',
      String url = 'https://api.test/todos',
      Map<String, String> headers = const <String, String>{},
      BodySnapshot? body,
    }) =>
        NetworkEntry(
          id: 'req-1',
          method: method,
          url: url,
          startedAt: DateTime(2026, 10, 16),
          requestHeaders: headers,
          requestBody: body,
        );

    test('omits -X for a GET and includes the URL', () {
      expect(toCurlCommand(entry()), contains('curl https://api.test/todos'));
      expect(toCurlCommand(entry()), isNot(contains('-X GET')));
    });

    test('adds -X for other methods', () {
      expect(toCurlCommand(entry(method: 'DELETE')), contains('-X DELETE'));
    });

    test('includes headers and the body', () {
      final command = toCurlCommand(
        entry(
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: const BodySnapshot(
            kind: BodyKind.json,
            preview: '{"a":1}',
            byteLength: 7,
          ),
        ),
      );
      expect(command, contains('-H'));
      expect(command, contains('Content-Type: application/json'));
      expect(command, contains('--data-raw'));
      expect(command, contains('{"a":1}'));
    });

    test('quotes values a shell would otherwise interpret', () {
      final command = toCurlCommand(
        entry(
          headers: {'X-Note': 'a b'},
          body: const BodySnapshot(
            kind: BodyKind.text,
            preview: r'$HOME `whoami`',
            byteLength: 15,
          ),
        ),
      );
      // Single quotes: a shell expands nothing inside them, so `$HOME` and the
      // backticks stay literal.
      expect(command, contains("-H 'X-Note: a b'"));
      expect(command, contains(r"--data-raw '$HOME `whoami`'"));
    });

    test('escapes an embedded single quote the POSIX way', () {
      final command = toCurlCommand(
        entry(body: const BodySnapshot(
          kind: BodyKind.text,
          preview: "it's",
          byteLength: 4,
        )),
      );
      expect(command, contains(r"'it'\''s'"));
    });

    test('leaves a shell-safe value unquoted', () {
      expect(toCurlCommand(entry()), isNot(contains("'https://api.test/todos'")));
    });

    test('omits a binary body rather than sending an empty one', () {
      final command = toCurlCommand(
        entry(body: const BodySnapshot(
          kind: BodyKind.binary,
          preview: '',
          byteLength: 2048,
        )),
      );
      expect(command, isNot(contains('--data-raw')));
    });
  });

  group('formatting', () {
    test('formatBytes scales units', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(1024 * 1024 * 3), '3.0 MB');
    });

    test('formatDuration drops the space so it reads as one token', () {
      expect(formatDuration(const Duration(milliseconds: 140)), '140ms');
      expect(formatDuration(const Duration(milliseconds: 1500)), '1.5s');
      expect(formatDuration(null), '—');
    });
  });
}
