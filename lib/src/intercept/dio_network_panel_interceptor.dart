import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../core/entry.dart';
import '../core/format.dart';
import '../core/serializer.dart';
import '../store/network_store.dart';

/// Records every request that passes through a `Dio` instance.
///
/// ## Where to add it
///
/// ```dart
/// final dio = Dio();
/// dio.interceptors.add(DioNetworkPanelInterceptor(store: store));
/// ```
///
/// Add it **first**. dio runs request, response *and* error interceptors in list
/// order — it does not reverse the order for the response path the way most
/// middleware stacks do. Two consequences:
///
/// - A request that an earlier interceptor rejects never reaches a later
///   interceptor's `onRequest`, so an inspector added last silently misses those
///   requests. Added first, it always sees them.
/// - `onError` is attached to the end of the whole chain, so it fires for *every*
///   interceptor even when the failure happened before their `onRequest` ran.
///   This interceptor therefore treats "no entry id" as a normal case, not a bug.
///
/// Because it runs first, `onRequest` sees the request *before* other
/// interceptors have touched it. So the terminal callbacks re-read the request
/// side from the final [RequestOptions] — the same instance flows through the
/// chain, so by then it holds the headers and body that were actually sent.
class DioNetworkPanelInterceptor extends Interceptor {
  DioNetworkPanelInterceptor({required this.store});

  /// The store the panel reads from. Share one instance with the widget.
  final NetworkStore store;

  /// Key under which the entry id travels with the request.
  ///
  /// Carried in `RequestOptions.extra` rather than in a side table so it survives
  /// `copyWith`: an interceptor that replaces the options object would otherwise
  /// orphan the entry and the request would never be completed.
  static const String entryIdKey = 'dioNetworkPanelEntryId';

  bool _reportedFailure = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _safely('onRequest', () => _begin(options));
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _safely('onResponse', () => _finishSuccess(response));
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _safely('onError', () => _finishFailure(err));
    handler.next(err);
  }

  // ---------------------------------------------------------------- recording

  void _begin(RequestOptions options) {
    final config = store.config;
    if (!config.enabled) return;
    if (_isIgnored(options, config)) return;

    final id = store.begin(
      method: options.method,
      url: options.uri.toString(),
      headers: _flattenHeaders(options.headers),
      body: _describeRequestBody(options, config.bodyLimit),
    );

    // `RequestOptions.extra` is a `late` non-nullable map that the constructor
    // always populates, so it is safe to write into directly.
    options.extra[entryIdKey] = id;
  }

  void _finishSuccess(Response<dynamic> response) {
    final options = response.requestOptions;
    final id = _entryIdOf(options);
    if (id == null) return;

    final config = store.config;
    final status = response.statusCode ?? 0;
    final succeeded = status >= 200 && status < 400;
    final headers = redactHeaders(
      _flattenHeaders(response.headers.map),
      config.redactedHeaders,
    );
    final body = _describeResponseBody(response, config.bodyLimit);

    store.patch(
      id,
      (current) => current.copyWith(
        method: options.method,
        url: options.uri.toString(),
        requestHeaders: redactHeaders(
          _flattenHeaders(options.headers),
          config.redactedHeaders,
        ),
        requestBody: _describeRequestBody(options, config.bodyLimit),
        state: succeeded ? NetworkState.success : NetworkState.error,
        duration: _elapsedSince(current.startedAt),
        statusCode: status,
        statusMessage: response.statusMessage,
        responseHeaders: headers,
        responseBody: body,
        responseBytes: body?.byteLength,
        // `copyWith` treats null as "keep the existing value", and the entry
        // starts with a null failureKind, so this is correct in both branches.
        failureKind: succeeded ? null : NetworkFailure.badResponse,
        failureLabel: succeeded ? null : 'badResponse',
      ),
    );
  }

  void _finishFailure(DioException err) {
    final options = err.requestOptions;
    final id = _entryIdOf(options);
    if (id == null) return;

    final config = store.config;
    final failure = _mapFailure(err.type);
    final response = err.response;
    final headers = response == null
        ? const <String, String>{}
        : redactHeaders(
            _flattenHeaders(response.headers.map),
            config.redactedHeaders,
          );
    final body = response == null
        ? null
        : _describeResponseBody(response, config.bodyLimit);

    store.patch(
      id,
      (current) => current.copyWith(
        method: options.method,
        url: options.uri.toString(),
        requestHeaders: redactHeaders(
          _flattenHeaders(options.headers),
          config.redactedHeaders,
        ),
        requestBody: _describeRequestBody(options, config.bodyLimit),
        state: _stateFor(failure),
        duration: _elapsedSince(current.startedAt),
        statusCode: response?.statusCode,
        statusMessage: response?.statusMessage,
        responseHeaders: headers,
        responseBody: body,
        responseBytes: body?.byteLength,
        errorMessage: _describeError(err),
        failureKind: failure,
        failureLabel: err.type.name,
      ),
    );
  }

  // ------------------------------------------------------------------ helpers

  /// Runs [body], swallowing anything it throws.
  ///
  /// A bug in a debugging tool must never break the request it is observing —
  /// if this throws out of `onRequest`, the app's request fails.
  ///
  /// The first failure is reported once. Reporting every occurrence would bury
  /// the app's own logs under one line per request.
  void _safely(String where, void Function() body) {
    try {
      body();
    } catch (error, stackTrace) {
      if (_reportedFailure) return;
      _reportedFailure = true;
      debugPrint(
        'flutter_dio_inspector: $where failed, this request was not recorded.\n'
        '$error\n$stackTrace',
      );
    }
  }

  String? _entryIdOf(RequestOptions options) {
    final raw = options.extra[entryIdKey];
    return raw is String ? raw : null;
  }

  bool _isIgnored(RequestOptions options, NetworkPanelConfig config) {
    final ignore = config.ignore;
    if (ignore == null) return false;
    try {
      return ignore(options.uri, options.method.toUpperCase());
    } catch (error) {
      // A throwing predicate must not silence the whole panel.
      _reportOnce('the ignore predicate', error);
      return false;
    }
  }

  void _reportOnce(String what, Object error) {
    if (_reportedFailure) return;
    _reportedFailure = true;
    debugPrint('flutter_dio_inspector: $what threw and is being ignored: $error');
  }

  Duration _elapsedSince(DateTime startedAt) =>
      DateTime.now().difference(startedAt);

  static NetworkState _stateFor(NetworkFailure failure) => switch (failure) {
        NetworkFailure.timeout => NetworkState.timeout,
        NetworkFailure.canceled => NetworkState.canceled,
        _ => NetworkState.error,
      };

  /// Maps dio's exception type onto the panel's own vocabulary.
  ///
  /// dio names every timeout variant `*Timeout` — `connectionTimeout`,
  /// `sendTimeout`, `receiveTimeout`, and `transformTimeout` since 5.10. Matching
  /// on the suffix rather than listing the members does two things: this package
  /// still compiles against dio versions that predate `transformTimeout`, and a
  /// timeout variant added in a future release is classified correctly instead of
  /// being bucketed as `unknown`.
  ///
  /// The remaining cases use the enum directly, with a wildcard so that a new dio
  /// type cannot break a consumer's build on `dart pub upgrade`. The exact name is
  /// always kept in `NetworkEntry.failureLabel`, so nothing is lost.
  static NetworkFailure _mapFailure(DioExceptionType type) {
    if (type.name.endsWith('Timeout')) return NetworkFailure.timeout;
    return switch (type) {
      DioExceptionType.cancel => NetworkFailure.canceled,
      DioExceptionType.badResponse => NetworkFailure.badResponse,
      DioExceptionType.badCertificate => NetworkFailure.certificate,
      DioExceptionType.connectionError => NetworkFailure.connection,
      _ => NetworkFailure.unknown,
    };
  }

  static String _describeError(DioException err) {
    final message = err.message?.trim();
    if (message != null && message.isNotEmpty) return message;
    final cause = err.error;
    if (cause != null) return cause.toString();
    return err.type.name;
  }

  // ------------------------------------------------------------- body capture

  static Map<String, String> _flattenHeaders(Map<String, dynamic> headers) {
    final result = <String, String>{};
    headers.forEach((key, value) {
      if (value == null) return;
      result[key] = value is Iterable<Object?>
          ? value.join(', ')
          : value.toString();
    });
    return result;
  }

  static String? _requestContentType(RequestOptions options) {
    final declared = options.contentType;
    if (declared != null && declared.isNotEmpty) return declared;
    return headerValue(_flattenHeaders(options.headers), 'content-type');
  }

  static String? _headerFirst(Headers headers, String name) {
    final values = headers[name];
    if (values == null || values.isEmpty) return null;
    return values.first;
  }

  static BodySnapshot? _describeRequestBody(
    RequestOptions options,
    int byteLimit,
  ) {
    final data = options.data;
    if (data == null) return null;

    final mimeType = _requestContentType(options);

    if (data is FormData) {
      return _describeFormData(data, byteLimit, mimeType);
    }
    if (data is Stream) {
      // Reading it here would consume the payload the adapter is about to send.
      return streamSnapshot(mimeType: mimeType);
    }
    return snapshotData(data, byteLimit: byteLimit, mimeType: mimeType);
  }

  static BodySnapshot? _describeResponseBody(
    Response<dynamic> response,
    int byteLimit,
  ) {
    final data = response.data;
    if (data == null) return null;

    final mimeType = _headerFirst(response.headers, Headers.contentTypeHeader);

    if (data is ResponseBody || data is Stream) {
      // `ResponseType.stream`: the caller is going to read this stream, so the
      // inspector must not touch it. Size and MIME type are all it gets.
      return streamSnapshot(mimeType: mimeType);
    }
    return snapshotData(data, byteLimit: byteLimit, mimeType: mimeType);
  }

  /// Summarises a multipart body instead of dumping it.
  ///
  /// Serialising it would mean consuming the file streams, which breaks the
  /// request. Field values and file names are what a developer actually needs to
  /// see anyway; the bytes are not.
  ///
  /// Safe to call after `FormData.finalize()`: that only sets a flag, it does not
  /// clear `fields` or `files`.
  static BodySnapshot _describeFormData(
    FormData form,
    int byteLimit,
    String? mimeType,
  ) {
    final buffer = StringBuffer();
    for (final field in form.fields) {
      buffer.writeln('${field.key} = ${field.value}');
    }
    for (final file in form.files) {
      final multipart = file.value;
      buffer.writeln(
        '${file.key} = <file ${multipart.filename ?? '(unnamed)'}, '
        '${formatBytes(multipart.length)}>',
      );
    }

    final description = buffer.toString().trimRight();
    return textSnapshot(
      description.isEmpty ? '<empty multipart body>' : description,
      byteLimit: byteLimit,
      mimeType: mimeType ?? Headers.multipartFormDataContentType,
    );
  }
}
