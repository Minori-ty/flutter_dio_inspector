import 'package:flutter_dio_inspector/flutter_dio_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeJson', () {
    test('reads an object', () {
      final result = decodeJson('{"a": 1}');
      expect(result.ok, isTrue);
      expect(result.value, <String, Object?>{'a': 1});
    });

    test('reads an array', () {
      final result = decodeJson('[1, 2, 3]');
      expect(result.ok, isTrue);
      expect(result.value, <Object?>[1, 2, 3]);
    });

    test('a literal null is valid JSON, not a failure', () {
      // The reason this returns a record rather than a nullable value: a body of
      // `null` and a body of `not json` must not look the same.
      final result = decodeJson('null');
      expect(result.ok, isTrue);
      expect(result.value, isNull);
    });

    test('reports malformed input instead of throwing', () {
      expect(decodeJson('not json').ok, isFalse);
      expect(decodeJson('{"a": }').ok, isFalse);
      expect(decodeJson('').ok, isFalse);
    });

    test('reports a truncated document, which is what a capped body looks like', () {
      expect(decodeJson('{"items": [1, 2, ').ok, isFalse);
    });

    test('tolerates surrounding whitespace', () {
      expect(decodeJson('\n  {"a":1}\n').ok, isTrue);
    });
  });

  group('isJsonContainer', () {
    test('is true for objects and arrays', () {
      expect(isJsonContainer(<String, Object?>{}), isTrue);
      expect(isJsonContainer(<Object?>[]), isTrue);
    });

    test('is false for primitives', () {
      expect(isJsonContainer(null), isFalse);
      expect(isJsonContainer('x'), isFalse);
      expect(isJsonContainer(1), isFalse);
      expect(isJsonContainer(true), isFalse);
    });
  });

  group('jsonChildCount', () {
    test('counts direct entries only', () {
      expect(jsonChildCount(<String, Object?>{'a': 1, 'b': 2}), 2);
      expect(
        jsonChildCount(<Object?>[
          <Object?>[1, 2, 3],
        ]),
        1,
      );
    });

    test('is zero for primitives', () {
      expect(jsonChildCount('x'), 0);
      expect(jsonChildCount(null), 0);
    });
  });
}
