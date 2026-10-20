import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dio_inspector/flutter_dio_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Responder = Future<ResponseBody> Function(RequestOptions options);

/// Stands in for the real HTTP adapter so tests never touch the network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responder);

  final _Responder responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      responder(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(String body, [int statusCode = 200]) =>
    ResponseBody.fromString(
      body,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );

void main() {
  late NetworkStore store;
  late Dio dio;

  setUp(() {
    store = NetworkStore();
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..interceptors.add(DioNetworkPanelInterceptor(store: store))
      ..httpClientAdapter = _FakeAdapter((_) async => _jsonBody('{"ok":true}'));
  });

  group('happy path', () {
    test('records one entry per request, with the resolved URL', () async {
      await dio.get('/todos');

      expect(store.entries, hasLength(1));
      final entry = store.entries.single;
      expect(entry.method, 'GET');
      expect(entry.url, 'https://api.test/todos');
      expect(entry.state, NetworkState.success);
      expect(entry.statusCode, 200);
      expect(entry.duration, isNotNull);
    });

    test('captures a JSON request body', () async {
      await dio.post('/todos', data: <String, Object?>{'title': 'ship it'});

      final entry = store.entries.single;
      expect(entry.method, 'POST');
      expect(entry.requestBody!.kind, BodyKind.json);
      expect(entry.requestBody!.preview, '{"title":"ship it"}');
    });

    test('captures the decoded response body and its size', () async {
      await dio.get('/todos');

      final entry = store.entries.single;
      expect(entry.responseBody!.kind, BodyKind.json);
      expect(entry.responseBody!.preview, contains('"ok"'));
      expect(entry.responseBytes, greaterThan(0));
    });

    test('query parameters end up in the recorded URL', () async {
      await dio.get('/todos', queryParameters: <String, Object?>{'limit': 10});

      final entry = store.entries.single;
      expect(entry.url, 'https://api.test/todos?limit=10');
      expect(entry.displayPath, '/todos?limit=10');
    });
  });

  group('failures', () {
    test('a 404 is an error carrying the response', () async {
      dio.httpClientAdapter = _FakeAdapter(
        (_) async => ResponseBody.fromString(
          '{"error":"gone"}',
          404,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        ),
      );

      await expectLater(dio.get('/missing'), throwsA(isA<DioException>()));

      final entry = store.entries.single;
      expect(entry.state, NetworkState.error);
      expect(entry.failureKind, NetworkFailure.badResponse);
      expect(entry.failureLabel, 'badResponse');
      expect(entry.statusCode, 404);
      expect(entry.responseBody, isNotNull);
    });

    test('a connect timeout is classified as a timeout, not a generic error', () async {
      dio.httpClientAdapter = _FakeAdapter(
        (options) async => throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: options,
        ),
      );

      await expectLater(dio.get('/slow'), throwsA(isA<DioException>()));

      final entry = store.entries.single;
      expect(entry.state, NetworkState.timeout);
      expect(entry.failureKind, NetworkFailure.timeout);
      expect(entry.failureLabel, 'connectionTimeout');
      expect(entry.errorMessage, isNotEmpty);
    });

    test('a receive timeout is a timeout too', () async {
      dio.httpClientAdapter = _FakeAdapter(
        (options) async => throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 1),
          requestOptions: options,
        ),
      );

      await expectLater(dio.get('/slow'), throwsA(isA<DioException>()));
      expect(store.entries.single.state, NetworkState.timeout);
    });

    test('a cancellation is classified as canceled', () async {
      dio.httpClientAdapter = _FakeAdapter(
        (options) async => throw DioException.requestCancelled(
          requestOptions: options,
          reason: 'the screen was closed',
        ),
      );

      await expectLater(dio.get('/x'), throwsA(isA<DioException>()));

      final entry = store.entries.single;
      expect(entry.state, NetworkState.canceled);
      expect(entry.failureKind, NetworkFailure.canceled);
      expect(entry.failureLabel, 'cancel');
    });

    test('a socket failure is classified as a connection error', () async {
      dio.httpClientAdapter = _FakeAdapter(
        (options) async => throw DioException.connectionError(
          requestOptions: options,
          reason: 'connection refused',
        ),
      );

      await expectLater(dio.get('/x'), throwsA(isA<DioException>()));

      final entry = store.entries.single;
      expect(entry.state, NetworkState.error);
      expect(entry.failureKind, NetworkFailure.connection);
      expect(entry.errorMessage, contains('connection refused'));
    });
  });

  group('interceptor ordering', () {
    test('a request rejected by a later interceptor is still recorded', () async {
      // dio runs request interceptors in list order, so a blocker appended after
      // ours only fires once our onRequest has already created the entry.
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(requestOptions: options, message: 'blocked by test'),
            true,
          ),
        ),
      );

      await expectLater(dio.get('/blocked'), throwsA(isA<DioException>()));

      expect(store.entries, hasLength(1));
      expect(store.entries.single.state, NetworkState.error);
      expect(store.entries.single.errorMessage, 'blocked by test');
    });

    test('a rejection without callFollowingErrorInterceptor leaves the entry '
        'pending, because dio never calls onError', () async {
      // Measured behaviour, not a guess: `handler.reject(err)` defaults
      // callFollowingErrorInterceptor to false, which completes the chain with
      // `InterceptorResultType.reject` — a *value*, not a Future error. dio's
      // error handlers are attached with `catchError`, so none of them run.
      //
      // There is no hook that can observe this, so the entry stays pending. The
      // panel says so in the detail view rather than pretending otherwise, and
      // the README documents it.
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(requestOptions: options, message: 'blocked silently'),
          ),
        ),
      );

      await expectLater(dio.get('/blocked'), throwsA(isA<DioException>()));

      expect(store.entries, hasLength(1));
      expect(store.entries.single.state, NetworkState.pending);
      expect(store.entries.single.errorMessage, isNull);
    });

    test('headers added by a later interceptor still reach the entry', () async {
      // The inspector runs first, so it cannot see this header at onRequest time.
      // It re-reads the request at the terminal callback, where the header exists.
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.headers['X-Trace'] = 'trace-123';
            handler.next(options);
          },
        ),
      );

      await dio.get('/traced');

      expect(store.entries.single.requestHeaders['X-Trace'], 'trace-123');
    });

    test('a second interceptor does not produce a second entry', () async {
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.next(o)));

      await dio.get('/x');

      expect(store.entries, hasLength(1));
    });
  });

  group('filtering and redaction', () {
    test('keeps the Authorization header readable by default', () async {
      await dio.get(
        '/me',
        options: Options(headers: <String, Object?>{'Authorization': 'Bearer t'}),
      );

      // A debug panel that hides the one header you opened it to read is not
      // debugging anything. Redaction is opt-in.
      final headers = store.entries.single.requestHeaders;
      expect(headers['Authorization'], 'Bearer t');
    });

    test('redacts the configured headers when asked to', () async {
      store.config = const NetworkPanelConfig(redactedHeaders: sensitiveHeaders);

      await dio.get(
        '/me',
        options: Options(headers: <String, Object?>{'Authorization': 'Bearer t'}),
      );

      final headers = store.entries.single.requestHeaders;
      expect(headers['Authorization'], redactedPlaceholder);
    });

    test('the ignore predicate skips a request entirely', () async {
      store.config = NetworkPanelConfig(
        ignore: (uri, method) => uri.path.startsWith('/health'),
      );

      await dio.get('/health');

      expect(store.entries, isEmpty);
    });

    test('a disabled store records nothing but still performs the request', () async {
      store.config = const NetworkPanelConfig(enabled: false);

      final response = await dio.get('/x');

      expect(response.statusCode, 200);
      expect(store.entries, isEmpty);
    });

    test('a throwing ignore predicate does not break the request', () async {
      store.config = NetworkPanelConfig(
        ignore: (uri, method) => throw StateError('bad predicate'),
      );

      final response = await dio.get('/x');

      expect(response.statusCode, 200);
      // The request is recorded rather than silently dropped: a broken predicate
      // must not take the whole panel down with it.
      expect(store.entries, hasLength(1));
    });
  });

  group('body shapes that must not be consumed', () {
    test('a streamed response is not read, and the caller can still consume it', () async {
      dio.httpClientAdapter = _FakeAdapter(
        (_) async => ResponseBody.fromString('hello stream', 200),
      );

      final response = await dio.get<ResponseBody>(
        '/stream',
        options: Options(responseType: ResponseType.stream),
      );

      final entry = store.entries.single;
      expect(entry.state, NetworkState.success);
      expect(entry.responseBody!.kind, BodyKind.stream);
      expect(entry.responseBody!.preview, isEmpty);

      // The real proof: the payload is still there for the caller.
      final text = await utf8.decodeStream(response.data!.stream);
      expect(text, 'hello stream');
    });

    test('multipart form data is summarised, not serialised', () async {
      await dio.post(
        '/upload',
        data: FormData.fromMap(<String, Object?>{
          'name': 'ada',
          'file': MultipartFile.fromBytes(
            <int>[1, 2, 3],
            filename: 'avatar.png',
          ),
        }),
      );

      final body = store.entries.single.requestBody!;
      expect(body.kind, BodyKind.form);
      expect(body.preview, contains('name = ada'));
      expect(body.preview, contains('avatar.png'));
      expect(body.preview, contains('3 B'));
    });

    test('a bytes response is recorded by size only', () async {
      dio.httpClientAdapter = _FakeAdapter(
        (_) async => ResponseBody.fromBytes(<int>[1, 2, 3, 4, 5], 200),
      );

      await dio.get<List<int>>(
        '/blob',
        options: Options(responseType: ResponseType.bytes),
      );

      final entry = store.entries.single;
      expect(entry.responseBody!.kind, BodyKind.binary);
      expect(entry.responseBody!.byteLength, 5);
      expect(entry.responseBody!.preview, isEmpty);
    });
  });

  group('store limits applied through the interceptor', () {
    test('the count limit evicts the oldest entry', () async {
      store.config = const NetworkPanelConfig(maxEntries: 2);

      for (final path in <String>['/a', '/b', '/c']) {
        await dio.get(path);
      }

      expect(store.entries.map((entry) => entry.url), <String>[
        'https://api.test/c',
        'https://api.test/b',
      ]);
      expect(store.evictedCount, 1);
    });

    test('clear empties the list', () async {
      await dio.get('/a');
      expect(store.entries, hasLength(1));

      store.clear();
      expect(store.entries, isEmpty);
    });
  });
}
