import 'package:dio/dio.dart';
import 'package:flutter_dio_inspector/flutter_dio_inspector.dart';
import 'package:flutter_dio_inspector/src/ui/filter_bar.dart';
import 'package:flutter_dio_inspector/src/ui/primitives.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Seeds a finished entry straight into the store.
///
/// Widget tests should not depend on the interceptor, so the store is populated
/// directly and the interceptor has its own test file.
String seedRequest(
  NetworkStore store, {
  String method = 'GET',
  String path = '/todos',
  int status = 200,
  String body = '{"ok":true}',
  BodyKind bodyKind = BodyKind.json,
  String? errorMessage,
  NetworkState state = NetworkState.success,
}) {
  final id = store.begin(
    method: method,
    url: 'https://api.test$path',
    headers: const <String, String>{'accept': 'application/json'},
  );
  store.patch(
    id,
    (NetworkEntry current) => current.copyWith(
      state: state,
      statusCode: status,
      statusMessage: 'OK',
      duration: const Duration(milliseconds: 140),
      responseHeaders: const <String, String>{
        'content-type': 'application/json',
      },
      responseBody: BodySnapshot(
        kind: bodyKind,
        preview: body,
        byteLength: body.length,
      ),
      responseBytes: body.length,
      errorMessage: errorMessage,
    ),
  );
  return id;
}

class _FakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        '{"ok":true}',
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );

  @override
  void close({bool force = false}) {}
}

Future<GlobalKey<NavigatorState>> pumpPanel(
  WidgetTester tester,
  NetworkStore store, {
  bool hideBall = false,
  /// Which language to pin the panel to. `null` leaves the panel to create its
  /// own controller, which is how the default gets exercised.
  PanelLanguage? language = PanelLanguage.zh,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  // Pinned to Chinese by default here: the panel itself defaults to English, and
  // every assertion below is written against the Chinese strings.
  final languageController =
      language == null ? null : PanelLanguageController(initial: language);
  if (languageController != null) addTearDown(languageController.dispose);

  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      builder: (BuildContext context, Widget? child) => DioNetworkPanel(
        store: store,
        navigatorKey: navigatorKey,
        hideBall: hideBall,
        languageController: languageController,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(body: Center(child: Text('home-screen'))),
    ),
  );
  return navigatorKey;
}

/// The badge only, so a stray "1" elsewhere on screen cannot satisfy the finder.
Finder badgeText(String value) => find.descendant(
      of: find.byType(FloatBall),
      matching: find.text(value),
    );

Future<void> openPanel(WidgetTester tester) async {
  await tester.tap(find.byType(FloatBall));
  await tester.pumpAndSettle();
}

/// Taps a section header to fold or unfold it.
Future<void> toggleSection(WidgetTester tester, String title) async {
  await tester.tap(find.textContaining(title));
  await tester.pumpAndSettle();
}

Future<void> goBack(WidgetTester tester, GlobalKey<NavigatorState> key) async {
  key.currentState!.pop();
  await tester.pumpAndSettle();
}

void main() {
  late NetworkStore store;

  setUp(() {
    store = NetworkStore();
    // There is no platform behind the test binding, so a real `Clipboard.setData`
    // would raise MissingPluginException and the toast would say "复制失败".
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async => null,
    );
  });
  tearDown(() => store.dispose());

  testWidgets('shows the ball with no badge when nothing was captured',
      (WidgetTester tester) async {
    await pumpPanel(tester, store);

    expect(find.byType(FloatBall), findsOneWidget);
    expect(badgeText('1'), findsNothing);
  });

  testWidgets('the badge counts unread requests and clears once the panel closes',
      (WidgetTester tester) async {
    await pumpPanel(tester, store);

    seedRequest(store);
    await tester.pump();
    expect(badgeText('1'), findsOneWidget);

    seedRequest(store);
    await tester.pump();
    expect(badgeText('2'), findsOneWidget);

    await openPanel(tester);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    expect(badgeText('2'), findsNothing);
  });

  testWidgets('the empty store explains what to do', (WidgetTester tester) async {
    await pumpPanel(tester, store);
    await openPanel(tester);

    expect(find.textContaining('还没有捕获到请求'), findsOneWidget);
  });

  testWidgets('the header switch flips the panel between Chinese and English',
      (WidgetTester tester) async {
    await pumpPanel(tester, store);
    seedRequest(store);
    await tester.pump();
    await openPanel(tester);

    expect(find.text('网络'), findsOneWidget);
    expect(find.text('清空'), findsOneWidget);

    // The button names the language it switches *to*, so the label says what a
    // tap will do rather than what is already on screen.
    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();

    expect(find.text('Network'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('网络'), findsNothing);
    expect(find.text('清空'), findsNothing);

    // Rows and filters are translated too, not just the header.
    expect(find.text('Search URL or method'), findsOneWidget);
    expect(find.text('/todos'), findsOneWidget);

    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();

    expect(find.text('网络'), findsOneWidget);
    expect(find.text('Network'), findsNothing);
  });

  testWidgets('a panel opened in English needs no switch',
      (WidgetTester tester) async {
    await pumpPanel(tester, store, language: PanelLanguage.en);
    await openPanel(tester);

    expect(find.text('Network'), findsOneWidget);
    expect(find.textContaining('No requests captured'), findsOneWidget);
  });

  testWidgets('with no controller the panel starts in English',
      (WidgetTester tester) async {
    // No controller passed at all: the panel builds its own, and the default has
    // to be English without asking the platform.
    await pumpPanel(tester, store, language: null);
    await openPanel(tester);

    expect(find.text('Network'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    expect(find.text('网络'), findsNothing);
  });

  testWidgets('the header still fits on a narrow phone',
      (WidgetTester tester) async {
    // Three text actions plus the title is the tightest the header has been. A
    // `RenderFlex` overflow would surface as a framework exception, which fails
    // the test by itself.
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPanel(tester, store);
    seedRequest(store);
    await tester.pump();
    await openPanel(tester);

    expect(find.text('EN'), findsOneWidget);
    expect(find.text('清空'), findsOneWidget);
    expect(find.text('关闭'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the detail page follows the language chosen in the list',
      (WidgetTester tester) async {
    await pumpPanel(tester, store);
    seedRequest(store);
    await tester.pump();
    await openPanel(tester);

    await tester.tap(find.text('EN'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(EntryTile).first);
    await tester.pumpAndSettle();

    // Section headers are upper-cased by `SectionHeader`, in both languages.
    expect(find.text('OVERVIEW'), findsOneWidget);
    expect(find.textContaining('REQUEST HEADERS · 1 ITEM'), findsOneWidget);
    expect(find.byTooltip('Copy request headers'), findsOneWidget);
  });

  testWidgets('opening a row clears its NEW marker', (WidgetTester tester) async {
    final navigatorKey = await pumpPanel(tester, store);
    seedRequest(store);
    await tester.pump();

    await openPanel(tester);
    expect(find.text('NEW'), findsOneWidget);

    await tester.tap(find.byType(EntryTile).first);
    await tester.pumpAndSettle();

    await goBack(tester, navigatorKey);
    expect(find.text('NEW'), findsNothing);
  });

  testWidgets('back unwinds detail then list', (WidgetTester tester) async {
    final navigatorKey = await pumpPanel(tester, store);
    seedRequest(store);
    await tester.pump();

    await openPanel(tester);
    expect(find.text('网络'), findsOneWidget);

    await tester.tap(find.byType(EntryTile).first);
    await tester.pumpAndSettle();
    expect(find.text('开始时间'), findsOneWidget);

    await goBack(tester, navigatorKey);
    expect(find.text('开始时间'), findsNothing);
    expect(find.text('网络'), findsOneWidget);

    await goBack(tester, navigatorKey);
    expect(find.text('网络'), findsNothing);
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('the detail page shows the URL, headers and body',
      (WidgetTester tester) async {
    await pumpPanel(tester, store);
    seedRequest(store);
    await tester.pump();

    await openPanel(tester);
    await tester.tap(find.byType(EntryTile).first);
    await tester.pumpAndSettle();

    expect(find.text('https://api.test/todos'), findsOneWidget);
    expect(find.text('概览'), findsOneWidget);
    expect(find.text('GET'), findsWidgets);
    expect(find.textContaining('"ok"'), findsWidgets);

    // The headers start folded, so they have to be opened before a header row is
    // in the tree at all.
    await toggleSection(tester, '请求头');
    expect(find.textContaining('accept'), findsWidgets);
  });

  testWidgets('tapping the URL copies it and confirms', (WidgetTester tester) async {
    await pumpPanel(tester, store);
    seedRequest(store);
    await tester.pump();

    await openPanel(tester);
    await tester.tap(find.byType(EntryTile).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('https://api.test/todos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('URL 已复制'), findsOneWidget);
  });

  testWidgets('a failed request shows its error in the list',
      (WidgetTester tester) async {
    await pumpPanel(tester, store);
    seedRequest(
      store,
      status: 500,
      state: NetworkState.error,
      errorMessage: '服务器炸了',
    );
    await tester.pump();

    await openPanel(tester);

    expect(find.text('500'), findsOneWidget);
    expect(find.text('服务器炸了'), findsOneWidget);
    expect(find.text('1 失败'), findsNothing);
    expect(find.textContaining('1 失败'), findsOneWidget);
  });

  testWidgets('the status code is regular weight, not bold',
      (WidgetTester tester) async {
    await pumpPanel(tester, store);
    seedRequest(store);
    await tester.pump();
    await openPanel(tester);

    final status = tester.widget<Text>(
      find.descendant(of: find.byType(EntryTile), matching: find.text('200')),
    );

    // The colour already says whether a request succeeded; a bold code competed
    // with the path on every row.
    expect(status.style?.fontWeight, FontWeight.w400);
  });

  testWidgets('the method filter narrows the list', (WidgetTester tester) async {
    await pumpPanel(tester, store);
    seedRequest(store, method: 'GET', path: '/a');
    seedRequest(store, method: 'POST', path: '/b');
    await tester.pump();

    await openPanel(tester);
    expect(find.byType(EntryTile), findsNWidgets(2));

    await tester.tap(
      find.descendant(of: find.byType(FilterBar), matching: find.text('POST')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EntryTile), findsOneWidget);
    expect(find.text('/b'), findsOneWidget);
  });

  testWidgets('the search field narrows the list', (WidgetTester tester) async {
    await pumpPanel(tester, store);
    seedRequest(store, path: '/alpha');
    seedRequest(store, path: '/beta');
    await tester.pump();

    await openPanel(tester);
    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pumpAndSettle();

    expect(find.byType(EntryTile), findsOneWidget);
    expect(find.text('/beta'), findsOneWidget);
  });

  testWidgets('hideBall renders only the child', (WidgetTester tester) async {
    await pumpPanel(tester, store, hideBall: true);

    expect(find.byType(FloatBall), findsNothing);
    expect(find.text('home-screen'), findsOneWidget);
  });

  testWidgets('the ball snaps to the nearer edge after a drag',
      (WidgetTester tester) async {
    await pumpPanel(tester, store);
    final before = tester.getCenter(find.byType(FloatBall));

    await tester.drag(find.byType(FloatBall), const Offset(-600, -40));
    await tester.pumpAndSettle();

    final after = tester.getCenter(find.byType(FloatBall));
    expect(after.dx, lessThan(before.dx));
    // Snapped to the left edge rather than left floating mid-screen.
    expect(after.dx, lessThan(80));
  });

  testWidgets('a request captured by the interceptor reaches the panel',
      (WidgetTester tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..interceptors.add(DioNetworkPanelInterceptor(store: store))
      ..httpClientAdapter = _FakeAdapter();

    // `runAsync` because dio's interceptor pipeline hops through `Future(...)`,
    // which is a zero-duration timer. Inside `testWidgets` timers only advance
    // when the test pumps, so awaiting the request directly would hang forever.
    await tester.runAsync(() => dio.get('/todos'));

    await pumpPanel(tester, store);
    await tester.pump();
    expect(badgeText('1'), findsOneWidget);

    await openPanel(tester);
    expect(find.byType(EntryTile), findsOneWidget);
    expect(find.text('/todos'), findsOneWidget);
  });

  group('JSON body', () {
    Future<void> openDetail(WidgetTester tester, {required String body, BodyKind bodyKind = BodyKind.json}) async {
      await pumpPanel(tester, store);
      seedRequest(store, body: body, bodyKind: bodyKind);
      await tester.pump();
      await openPanel(tester);
      await tester.tap(find.byType(EntryTile).first);
      await tester.pumpAndSettle();
    }

    testWidgets('a JSON response body is rendered as a foldable tree',
        (WidgetTester tester) async {
      await openDetail(tester, body: '{"ok": true, "nested": {"a": 1}}');

      expect(find.byType(JsonTreeView), findsOneWidget);
      expect(find.textContaining('"nested"'), findsOneWidget);
    });

    testWidgets('the fold controls in the section header drive the tree',
        (WidgetTester tester) async {
      await openDetail(tester, body: '{"ok": true, "nested": {"a": 1}}');

      await tester.tap(find.byTooltip('全部折叠'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"nested"'), findsNothing);
      expect(find.textContaining('2 字段'), findsOneWidget);

      await tester.tap(find.byTooltip('全部展开'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"a": 1'), findsOneWidget);
    });

    testWidgets('a body that is not JSON keeps the plain text view',
        (WidgetTester tester) async {
      await openDetail(
        tester,
        body: '<html><body>hi</body></html>',
        bodyKind: BodyKind.text,
      );

      expect(find.byType(JsonTreeView), findsNothing);
      expect(find.text('<html><body>hi</body></html>'), findsOneWidget);
      expect(find.byTooltip('全部展开'), findsNothing);
    });
  });

  group('the ball', () {
    testWidgets('is hidden while the panel is open', (WidgetTester tester) async {
      final navigatorKey = await pumpPanel(tester, store);
      seedRequest(store);
      await tester.pump();
      expect(find.byType(FloatBall), findsOneWidget);

      await openPanel(tester);
      // The ball lives above the Navigator, so without this it floats on top of
      // the panel it just opened.
      expect(find.byType(FloatBall), findsNothing);
      expect(find.text('网络'), findsOneWidget);

      await goBack(tester, navigatorKey);
      expect(find.byType(FloatBall), findsOneWidget);
    });

    testWidgets('straddles the ball\'s top-right edge',
        (WidgetTester tester) async {
      await pumpPanel(tester, store);
      seedRequest(store);
      await tester.pump();

      final ball = find.byType(FloatBall);
      final badge = find.descendant(of: ball, matching: find.text('1'));
      expect(badge, findsOneWidget);

      final ballRect = tester.getRect(ball);
      final badgeRect = tester.getRect(badge);
      final ballRadius = ballRect.width / 2;
      final distance = (badgeRect.center - ballRect.center).distance;

      // Up and to the right of the centre.
      expect(badgeRect.center.dx, greaterThan(ballRect.center.dx));
      expect(badgeRect.center.dy, lessThan(ballRect.center.dy));

      // Its centre sits on the ball's edge — the 45° point of the circle, not the
      // corner of its bounding box. Anchoring to the corner instead puts it
      // further out, far enough that the two circles stop intersecting and the
      // badge reads as a separate object floating beside the ball.
      expect(distance, closeTo(ballRadius, 4));
    });

    testWidgets('the badge text does not inherit the fallback underline',
        (WidgetTester tester) async {
      await pumpPanel(tester, store);
      seedRequest(store);
      await tester.pump();

      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.byType(FloatBall), matching: find.text('1')),
      );

      // `MaterialApp`'s fallback text style — applied when there is no `Material`
      // above the text — is monospace with a *double yellow underline* (see
      // `_errorTextStyle` in material/app.dart). Setting `color` does not clear
      // it, because `decoration` is inherited separately, which is why the digit
      // had two yellow lines under it.
      expect(
        paragraph.text.style?.decoration,
        anyOf(isNull, TextDecoration.none),
      );
    });

    testWidgets('the search field is tall enough to read',
        (WidgetTester tester) async {
      await pumpPanel(tester, store);
      seedRequest(store);
      await tester.pump();
      await openPanel(tester);

      expect(
        tester.getSize(find.byType(TextField)).height,
        greaterThanOrEqualTo(44),
      );
    });
  });

  group('collapsible sections', () {
    Future<void> openDetail(WidgetTester tester) async {
      await pumpPanel(tester, store);
      seedRequest(store);
      await tester.pump();
      await openPanel(tester);
      await tester.tap(find.byType(EntryTile).first);
      await tester.pumpAndSettle();
    }

    testWidgets('the headers start folded and the bodies start open',
        (WidgetTester tester) async {
      await openDetail(tester);

      // Header rows are not in the tree at all...
      expect(find.textContaining('accept:'), findsNothing);
      expect(find.textContaining('content-type:'), findsNothing);
      // ...but each header still says how much is inside it.
      expect(find.textContaining('请求头 · 1 项'), findsOneWidget);
      expect(find.textContaining('响应头 · 1 项'), findsOneWidget);
      // The bodies are the reason the detail was opened, so they are already up.
      expect(find.textContaining('"ok"'), findsWidgets);
    });

    testWidgets('tapping a header unfolds it, and again folds it back',
        (WidgetTester tester) async {
      await openDetail(tester);
      expect(find.textContaining('accept:'), findsNothing);

      await toggleSection(tester, '请求头');
      expect(find.textContaining('accept:'), findsOneWidget);

      await toggleSection(tester, '请求头');
      expect(find.textContaining('accept:'), findsNothing);
    });

    testWidgets('folding one header leaves the other alone',
        (WidgetTester tester) async {
      await openDetail(tester);

      await toggleSection(tester, '请求头');
      expect(find.textContaining('accept:'), findsOneWidget);
      expect(find.textContaining('content-type:'), findsNothing);

      await toggleSection(tester, '响应头');
      expect(find.textContaining('content-type:'), findsOneWidget);
    });

    testWidgets('the copy button stays available while a header is folded',
        (WidgetTester tester) async {
      await openDetail(tester);

      // Copying a header block is often the reason for coming here, so it should
      // not require unfolding first.
      expect(find.byTooltip('复制请求头'), findsOneWidget);
      expect(find.byTooltip('复制响应头'), findsOneWidget);
    });
  });

  group('alignment', () {
    testWidgets('header rows sit against the left edge of their card',
        (WidgetTester tester) async {
      await pumpPanel(tester, store);
      seedRequest(store);
      await tester.pump();
      await openPanel(tester);
      await tester.tap(find.byType(EntryTile).first);
      await tester.pumpAndSettle();

      // Both sections start folded.
      await toggleSection(tester, '请求头');
      await toggleSection(tester, '响应头');

      // Both are short rows, so a loose cross-axis constraint would centre them.
      for (final name in <String>['accept', 'content-type']) {
        final row = find.textContaining('$name:');
        expect(row, findsOneWidget, reason: 'expected a row for $name');

        final card = find.ancestor(of: row, matching: find.byType(SectionCard));
        expect(card, findsOneWidget);

        final cardLeft = tester.getRect(card).left;
        final rowLeft = tester.getRect(row).left;
        // The row's own 12px horizontal padding, and nothing more.
        expect(
          rowLeft - cardLeft,
          closeTo(12, 0.5),
          reason: '"$name" should be left-aligned, not centred',
        );
      }
    });

    testWidgets('section cards span the page width', (WidgetTester tester) async {
      await pumpPanel(tester, store);
      seedRequest(store);
      await tester.pump();
      await openPanel(tester);
      await tester.tap(find.byType(EntryTile).first);
      await tester.pumpAndSettle();

      await toggleSection(tester, '请求头');

      final pageWidth = tester.getSize(find.byType(NetworkEntryDetailPage)).width;
      final card = find.ancestor(
        of: find.textContaining('accept:'),
        matching: find.byType(SectionCard),
      );

      // 16px of ListView padding on each side.
      expect(tester.getRect(card).width, closeTo(pageWidth - 32, 1));
    });

    testWidgets('the search field spans the filter bar', (WidgetTester tester) async {
      await pumpPanel(tester, store);
      seedRequest(store);
      await tester.pump();
      await openPanel(tester);

      final pageWidth = tester.getSize(find.byType(NetworkPanelPage)).width;
      // 16px of padding on each side of the filter bar.
      expect(
        tester.getSize(find.byType(TextField)).width,
        closeTo(pageWidth - 32, 1),
      );
    });
  });
}
