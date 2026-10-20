import 'package:flutter_dio_inspector/flutter_dio_inspector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deep enough that the default expansion depth hides something.
const String _sample = '''
{
  "name": "ada",
  "age": 36,
  "active": true,
  "nickname": null,
  "tags": ["a", "b"],
  "address": {"city": "London", "geo": {"lat": 1.5, "lng": 2.5}}
}
''';

Future<JsonTreeController> pumpTree(
  WidgetTester tester, {
  String source = _sample,
  int? defaultDepth = 2,
}) async {
  final controller = JsonTreeController(defaultDepth: defaultDepth);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: JsonTreeView(
            source: source,
            theme: NetworkPanelTheme.light,
            controller: controller,
          ),
        ),
      ),
    ),
  );
  return controller;
}

/// Every colour used for a span whose text contains [needle].
///
/// Highlighting cannot be asserted with a finder, so the spans themselves are
/// inspected — which is also what makes this a real check rather than a check
/// that some text exists.
Set<Color> colorsFor(WidgetTester tester, String needle) {
  final colors = <Color>{};
  for (final richText in tester.widgetList<RichText>(find.byType(RichText))) {
    richText.text.visitChildren((InlineSpan span) {
      if (span is TextSpan && span.text != null && span.text!.contains(needle)) {
        final color = span.style?.color;
        if (color != null) colors.add(color);
      }
      return true;
    });
  }
  return colors;
}

void main() {
  group('rendering', () {
    testWidgets('shows one row per key, with the values inline',
        (WidgetTester tester) async {
      await pumpTree(tester);

      expect(find.textContaining('"name": "ada"'), findsOneWidget);
      expect(find.textContaining('"age": 36'), findsOneWidget);
      expect(find.textContaining('"active": true'), findsOneWidget);
      expect(find.textContaining('"nickname": null'), findsOneWidget);
    });

    testWidgets('labels array items with their index', (WidgetTester tester) async {
      await pumpTree(tester, source: '["a", "b"]');

      expect(find.textContaining('0: "a"'), findsOneWidget);
      expect(find.textContaining('1: "b"'), findsOneWidget);
    });

    testWidgets('renders an empty container inline, with nothing to fold',
        (WidgetTester tester) async {
      await pumpTree(tester, source: '{"empty": {}, "none": []}');

      expect(find.textContaining('"empty": {}'), findsOneWidget);
      expect(find.textContaining('"none": []'), findsOneWidget);
      // No ellipsis: an empty container is not a folded one. Only the root is
      // foldable here, so there is exactly one arrow.
      expect(find.textContaining('…'), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });
  });

  group('highlighting', () {
    testWidgets('gives each JSON type its own colour', (WidgetTester tester) async {
      await pumpTree(tester);
      const theme = NetworkPanelTheme.light;

      expect(colorsFor(tester, '"name"'), contains(theme.jsonKey));
      expect(colorsFor(tester, '"ada"'), contains(theme.jsonString));
      expect(colorsFor(tester, '36'), contains(theme.jsonNumber));
      expect(colorsFor(tester, 'true'), contains(theme.jsonBool));
      expect(colorsFor(tester, 'null'), contains(theme.jsonNull));
    });

    testWidgets('keys do not share the string colour', (WidgetTester tester) async {
      await pumpTree(tester);
      const theme = NetworkPanelTheme.light;

      expect(colorsFor(tester, '"name"'), isNot(contains(theme.jsonString)));
    });

    testWidgets('escapes a string value rather than printing it raw',
        (WidgetTester tester) async {
      await pumpTree(tester, source: '{"quote": "a\\"b", "nl": "a\\nb"}');

      // jsonEncode round-trips the escapes, so the row reads like the document.
      expect(find.textContaining(r'"quote": "a\"b"'), findsOneWidget);
      expect(find.textContaining(r'"nl": "a\nb"'), findsOneWidget);
    });

    testWidgets('a literal null body still gets the null colour, not plain text',
        (WidgetTester tester) async {
      await pumpTree(tester, source: 'null');

      // MonoBlock would render it in `theme.text`, so the colour proves it went
      // through the tree instead of the fallback.
      expect(
        colorsFor(tester, 'null'),
        contains(NetworkPanelTheme.light.jsonNull),
      );
    });
  });

  group('folding', () {
    testWidgets('collapses nodes deeper than the default depth',
        (WidgetTester tester) async {
      await pumpTree(tester);

      // `address` is at depth 1, so it is open and `geo` is visible; `geo` is at
      // depth 2, so its children are not.
      expect(find.textContaining('"city"'), findsOneWidget);
      expect(find.textContaining('"lat"'), findsNothing);
      // A collapsed node says what it is hiding.
      expect(find.textContaining('2 字段'), findsOneWidget);
    });

    testWidgets('tapping a collapsed node reveals its children',
        (WidgetTester tester) async {
      await pumpTree(tester);
      expect(find.textContaining('"lat"'), findsNothing);

      await tester.tap(find.textContaining('"geo"'));
      await tester.pumpAndSettle();

      expect(find.textContaining('"lat"'), findsOneWidget);
      expect(find.textContaining('"lng"'), findsOneWidget);
    });

    testWidgets('tapping again folds it back', (WidgetTester tester) async {
      await pumpTree(tester);

      await tester.tap(find.textContaining('"address"'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"city"'), findsNothing);

      await tester.tap(find.textContaining('"address"'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"city"'), findsOneWidget);
    });

    testWidgets('expandAll opens every container', (WidgetTester tester) async {
      final controller = await pumpTree(tester);
      expect(find.textContaining('"lat"'), findsNothing);

      controller.expandAll();
      await tester.pumpAndSettle();

      expect(find.textContaining('"lat"'), findsOneWidget);
      expect(find.textContaining('"lng"'), findsOneWidget);
    });

    testWidgets('collapseAll leaves only the root', (WidgetTester tester) async {
      final controller = await pumpTree(tester);

      controller.collapseAll();
      await tester.pumpAndSettle();

      expect(find.textContaining('"name"'), findsNothing);
      expect(find.textContaining('6 字段'), findsOneWidget);
    });

    testWidgets('collapseAll overrides a node the user had opened',
        (WidgetTester tester) async {
      final controller = await pumpTree(tester);

      await tester.tap(find.textContaining('"geo"'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"lat"'), findsOneWidget);

      controller.collapseAll();
      await tester.pumpAndSettle();
      expect(find.textContaining('"lat"'), findsNothing);

      // And the default depth is not silently restored afterwards.
      controller.expandAll();
      await tester.pumpAndSettle();
      expect(find.textContaining('"lat"'), findsOneWidget);
    });

    testWidgets('a foldable row says what it is and whether it is open',
        (WidgetTester tester) async {
      await pumpTree(tester);

      // Inspecting the Semantics widgets rather than the built semantics tree:
      // this is asserting the label this widget produces, not Flutter's plumbing.
      final labels = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((Semantics widget) => widget.properties.label)
          .whereType<String>();

      expect(labels, contains('address，已展开，2 字段'));
      expect(labels, contains('geo，已折叠，2 字段'));
    });
  });

  group('falling back to plain text', () {
    testWidgets('renders text that is not JSON as-is', (WidgetTester tester) async {
      await pumpTree(tester, source: 'not json at all');

      expect(find.text('not json at all'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('falls back for a document truncated at the capture limit',
        (WidgetTester tester) async {
      await pumpTree(tester, source: '{"items": [1, 2, ');

      expect(find.textContaining('{"items"'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('falls back for an empty body', (WidgetTester tester) async {
      await pumpTree(tester, source: '');

      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });
  });
}
