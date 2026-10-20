import 'package:flutter/foundation.dart';

import '../core/entry.dart';
import '../core/format.dart';
import 'panel_language.dart';

/// Every user-visible string in the panel, in Chinese and English.
///
/// One class with a ternary per string rather than a subclass per language: the
/// two translations sit next to each other, so a string added to one language and
/// forgotten in the other is visible in the diff instead of hiding in a second
/// file. Nothing here reads `BuildContext` — the strings are a plain value, which
/// keeps the widgets testable without a `MaterialApp`.
@immutable
class PanelStrings {
  const PanelStrings._(this.language);

  /// Chinese strings.
  static const PanelStrings zh = PanelStrings._(PanelLanguage.zh);

  /// English strings.
  static const PanelStrings en = PanelStrings._(PanelLanguage.en);

  /// The table for [language].
  static PanelStrings of(PanelLanguage language) =>
      language == PanelLanguage.zh ? zh : en;

  final PanelLanguage language;

  bool get _zh => language == PanelLanguage.zh;

  String _t(String zh, String en) => _zh ? zh : en;

  // ---------------------------------------------------------------- list page

  String get panelTitle => _t('网络', 'Network');

  String get clear => _t('清空', 'Clear');

  String get close => _t('关闭', 'Close');

  /// Label on the language button — the language it switches *to*, so the button
  /// says what a tap will do rather than what is currently shown.
  String get switchLanguageLabel => _t('EN', '中文');

  String get switchLanguageHint => _t('切换为英文', 'Switch to Chinese');

  String get emptyNoTraffic => _t(
        '还没有捕获到请求。\n发一个 dio 请求试试。',
        'No requests captured yet.\nFire a dio request and it will show up here.',
      );

  String get emptyFiltered => _t(
        '没有符合当前筛选条件的请求。',
        'No requests match the current filters.',
      );

  String failedCount(int count) =>
      _t('$count 失败', count == 1 ? '1 failed' : '$count failed');

  String evictedCount(int count) => _t('已淘汰 $count', '$count evicted');

  // ------------------------------------------------------------------ the ball

  String ballLabel(int unread) {
    if (unread <= 0) return _t('网络请求面板', 'Network panel');
    return _t(
      '网络请求面板，$unread 条未读',
      unread == 1
          ? 'Network panel, 1 unread request'
          : 'Network panel, $unread unread requests',
    );
  }

  // -------------------------------------------------------------------- filters

  String get searchHint => _t('搜索 URL 或方法', 'Search URL or method');

  String get clearSearch => _t('清除搜索', 'Clear search');

  // --------------------------------------------------------------------- detail

  String get detailTitle => _t('请求详情', 'Request details');

  String get copyCurl => _t('复制 cURL', 'Copy as cURL');

  String get entryEvicted => _t(
        '这条请求已被淘汰，或已被清空。',
        'This request was evicted, or the panel was cleared.',
      );

  String get overview => _t('概览', 'Overview');

  String get method => _t('方法', 'Method');

  String get startedAt => _t('开始时间', 'Started');

  String get duration => _t('耗时', 'Duration');

  String get status => _t('状态', 'Status');

  String get failureReason => _t('失败原因', 'Failure');

  String get responseSize => _t('响应大小', 'Size');

  String get sectionError => _t('错误', 'Error');

  String get requestHeaders => _t('请求头', 'Request headers');

  String get requestBody => _t('请求体', 'Request body');

  String get responseHeaders => _t('响应头', 'Response headers');

  String get responseBody => _t('响应体', 'Response body');

  /// How many headers a folded section holds.
  String itemCount(int count) =>
      _t('$count 项', count == 1 ? '1 item' : '$count items');

  String get emptyBody => _t('（空）', '(empty)');

  String get none => _t('（无）', '(none)');

  String get truncated => _t('已截断', 'truncated');

  String get expandAll => _t('全部展开', 'Expand all');

  String get collapseAll => _t('全部折叠', 'Collapse all');

  /// Tooltip for a copy button: `复制请求头` / `Copy request headers`.
  ///
  /// The English form drops the label's leading capital because it lands
  /// mid-sentence — the labels are also section titles, where the capital is
  /// right. Acronyms (`URL`, `JSON`) keep theirs, since lower-casing them would
  /// be worse than the inconsistency.
  String copyAction(String label) =>
      _t('复制$label', 'Copy ${_sentenceCase(label)}');

  static String _sentenceCase(String label) {
    if (label.length < 2) return label;
    final first = label[0];
    if (first != first.toUpperCase()) return label;
    final second = label[1];
    if (second == second.toUpperCase()) return label;
    return first.toLowerCase() + label.substring(1);
  }

  /// Toast after a successful copy.
  String copied(String label) => _t('$label 已复制', '$label copied');

  /// Toast after a failed copy.
  String copyFailed(String label) => _t('$label 复制失败', 'Could not copy $label');

  String get streamPlaceholder => _t(
        '（流，未读取——读取会消耗调用方要用的数据）',
        '(stream — not read, since reading it would consume the data your code '
            'needs)',
      );

  String binaryPlaceholder(int bytes) =>
      _t('（二进制，${formatBytes(bytes)}）', '(binary, ${formatBytes(bytes)})');

  /// Shown for a request that never reached a terminal state.
  String get pendingNote => _t(
        '还没有收到响应。如果这个请求被别的拦截器 reject() 了，而且没有传 '
            'callFollowingErrorInterceptor: true，dio 不会回调 onError，'
            '面板也就拿不到结果——这时它会一直停在进行中。',
        'No response yet. If another interceptor rejected this request with '
            'handler.reject() and did not pass callFollowingErrorInterceptor: '
            'true, dio never calls onError and the panel cannot see the outcome '
            '— so the row stays pending forever.',
      );

  // ---------------------------------------------------------- state and status

  String get statusTimeout => _t('超时', 'Timeout');

  String get statusCanceled => _t('取消', 'Canceled');

  String get statusFailed => _t('失败', 'Failed');

  /// The right-hand label for a row: the status code when there is one, else the
  /// outcome in words.
  String statusLabel(NetworkEntry entry) {
    final status = entry.statusCode;
    if (status != null) return '$status';
    switch (entry.state) {
      case NetworkState.pending:
        return '···';
      case NetworkState.timeout:
        return statusTimeout;
      case NetworkState.canceled:
        return statusCanceled;
      case NetworkState.error:
        return statusFailed;
      case NetworkState.success:
        return '—';
    }
  }

  /// Human-readable label for a failure reason.
  String failureLabel(NetworkFailure? failure) {
    switch (failure) {
      case null:
        return '—';
      case NetworkFailure.timeout:
        return statusTimeout;
      case NetworkFailure.canceled:
        return _t('已取消', 'Canceled');
      case NetworkFailure.badResponse:
        return _t('状态码被拒绝', 'Status rejected');
      case NetworkFailure.certificate:
        return _t('证书校验失败', 'Certificate rejected');
      case NetworkFailure.connection:
        return _t('连接失败', 'Connection failed');
      case NetworkFailure.unknown:
        return _t('未知错误', 'Unknown error');
    }
  }

  /// Coarse reason with dio's exact cause in brackets:
  /// `状态码被拒绝（badResponse）` / `Status rejected (badResponse)`.
  String failureWithCause(String coarse, String cause) =>
      _t('$coarse（$cause）', '$coarse ($cause)');

  /// Human-readable label for a captured body kind.
  String bodyKindLabel(BodyKind kind) {
    switch (kind) {
      case BodyKind.empty:
        return _t('空', 'Empty');
      case BodyKind.json:
        return 'JSON';
      case BodyKind.text:
        return _t('文本', 'Text');
      case BodyKind.form:
        return _t('表单', 'Form');
      case BodyKind.binary:
        return _t('二进制', 'Binary');
      case BodyKind.stream:
        return _t('流', 'Stream');
    }
  }

  // ------------------------------------------------------------------ json tree

  String _fieldCount(int count) =>
      _t('$count 字段', count == 1 ? '1 field' : '$count fields');

  String _itemCount(int count) =>
      _t('$count 项', count == 1 ? '1 item' : '$count items');

  /// The count shown after a collapsed container: `3 字段` / `3 fields`.
  String jsonCollapsedCount(int count, bool isMap) =>
      isMap ? _fieldCount(count) : _itemCount(count);

  /// Screen-reader description of a foldable node.
  String jsonNodeSemantics({
    String? label,
    required bool expanded,
    required int count,
    required bool isMap,
  }) {
    final name = label ?? _t('根节点', 'root');
    final state = expanded ? _t('已展开', 'expanded') : _t('已折叠', 'collapsed');
    return _t(
      '$name，$state，${jsonCollapsedCount(count, isMap)}',
      '$name, $state, ${jsonCollapsedCount(count, isMap)}',
    );
  }
}
