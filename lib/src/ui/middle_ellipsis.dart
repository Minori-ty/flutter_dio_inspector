import 'package:flutter/material.dart';

/// Truncates in the middle, keeping both ends of the string visible.
///
/// For a path, the leading segments and the query string are the informative
/// parts and the middle is the least interesting. End-truncation would drop the
/// query, which is usually the reason for looking at the row at all.
class MiddleEllipsisText extends StatelessWidget {
  const MiddleEllipsisText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  /// Measurements are memoised.
  ///
  /// Laying out a `TextPainter` once per row per frame is wasted work in a
  /// 200-row list, and the inputs (text, style, available width) rarely change
  /// between frames.
  static final Map<int, String> _cache = <int, String>{};
  static const int _cacheLimit = 512;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || maxWidth <= 0) {
          return _plain(text);
        }

        final direction = Directionality.of(context);
        final key = Object.hash(text, style, maxWidth.round(), direction);
        final fitted = _cache[key] ?? _fit(text, style, maxWidth, direction, key);

        return _plain(fitted);
      },
    );
  }

  Widget _plain(String value) => Text(
        value,
        style: style,
        maxLines: 1,
        textAlign: textAlign,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );

  String _fit(
    String value,
    TextStyle textStyle,
    double maxWidth,
    TextDirection direction,
    int cacheKey,
  ) {
    if (_widthOf(value, textStyle, direction) <= maxWidth) {
      return _remember(cacheKey, value);
    }

    // Binary search the longest prefix + suffix that still fits. Both ends are
    // kept because neither is dispensable.
    var low = 1;
    var high = value.length;
    var best = '…';
    while (low <= high) {
      final keep = (low + high) ~/ 2;
      final head = keep ~/ 2;
      final tail = keep - head;
      final candidate =
          '${value.substring(0, head)}…${value.substring(value.length - tail)}';
      if (_widthOf(candidate, textStyle, direction) <= maxWidth) {
        best = candidate;
        low = keep + 1;
      } else {
        high = keep - 1;
      }
    }
    return _remember(cacheKey, best);
  }

  static double _widthOf(String value, TextStyle style, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      maxLines: 1,
      textDirection: direction,
    )..layout();
    return painter.width;
  }

  static String _remember(int key, String value) {
    if (_cache.length >= _cacheLimit) _cache.clear();
    _cache[key] = value;
    return value;
  }
}
