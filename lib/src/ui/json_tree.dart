import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/json_preview.dart';
import '../i18n/panel_strings.dart';
import 'panel_theme.dart';
import 'primitives.dart';

/// One child of a JSON container, flattened for rendering.
typedef _JsonChild = ({String label, bool isIndex, Object? value});

/// Indentation per nesting level.
const double _indentStep = 14;

/// Width reserved for the disclosure arrow, so a leaf's text lines up with a
/// container's text at the same depth.
const double _twistyWidth = 18;

/// Drives expansion for a [JsonTreeView] from outside.
///
/// The expand-all / collapse-all buttons live in the section header, outside the
/// view, so the state has to be reachable from there.
///
/// State is keyed by **path**, built from child indices (`$/0/2`). Indices rather
/// than keys because a JSON key can contain any character, including whatever
/// separator a key-based path would use — and the tree for a given body never
/// changes shape, so indices are stable.
class JsonTreeController extends ChangeNotifier {
  JsonTreeController({int? defaultDepth = 2}) : _defaultDepth = defaultDepth;

  int? _defaultDepth;
  final Map<String, bool> _explicit = <String, bool>{};

  /// Depth below which nodes start out expanded. `null` means every node.
  int? get defaultDepth => _defaultDepth;

  bool isExpanded(String path, int depth) =>
      _explicit[path] ?? (_defaultDepth == null || depth < _defaultDepth!);

  void toggle(String path, int depth) {
    _explicit[path] = !isExpanded(path, depth);
    notifyListeners();
  }

  /// Opens every container.
  void expandAll() {
    _explicit.clear();
    _defaultDepth = null;
    notifyListeners();
  }

  /// Leaves only the root visible.
  void collapseAll() {
    _explicit.clear();
    _defaultDepth = 0;
    notifyListeners();
  }
}

/// A collapsible, syntax-highlighted JSON tree.
///
/// Falls back to plain text when the body does not parse. That is not a rare
/// path: a response larger than the capture limit is truncated mid-document, so
/// its JSON is genuinely invalid and there is nothing to fold.
class JsonTreeView extends StatefulWidget {
  const JsonTreeView({
    super.key,
    required this.source,
    required this.theme,
    required this.controller,
    this.strings = PanelStrings.zh,
  });

  final String source;
  final NetworkPanelTheme theme;
  final JsonTreeController controller;

  /// Wording for the fallback placeholder and the collapsed counts.
  final PanelStrings strings;

  @override
  State<JsonTreeView> createState() => _JsonTreeViewState();
}

class _JsonTreeViewState extends State<JsonTreeView> {
  JsonDecodeResult _decoded = (ok: false, value: null);

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(JsonTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Decoded once per body rather than once per build: this widget sits under a
    // ListenableBuilder on the store, so it rebuilds whenever any request
    // completes anywhere in the app.
    if (widget.source != oldWidget.source) _decode();
  }

  void _decode() => _decoded = decodeJson(widget.source);

  @override
  Widget build(BuildContext context) {
    if (!_decoded.ok) {
      return MonoBlock(
        text: widget.source,
        theme: widget.theme,
        placeholder: widget.strings.emptyBody,
      );
    }

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final rows = <Widget>[];
        _buildRows(
          rows: rows,
          path: r'$',
          depth: 0,
          label: null,
          isIndex: false,
          value: _decoded.value,
          isLast: true,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        );
      },
    );
  }

  void _buildRows({
    required List<Widget> rows,
    required String path,
    required int depth,
    required String? label,
    required bool isIndex,
    required Object? value,
    required bool isLast,
  }) {
    final children = _childrenOf(value);

    if (children == null) {
      rows.add(
        _JsonRow(
          depth: depth,
          theme: widget.theme,
          spans: <InlineSpan>[
            ..._labelSpans(label, isIndex),
            _valueSpan(value),
            if (!isLast) _punctuation(','),
          ],
        ),
      );
      return;
    }

    final isMap = value is Map;
    final open = isMap ? '{' : '[';
    final close = isMap ? '}' : ']';

    if (children.isEmpty) {
      rows.add(
        _JsonRow(
          depth: depth,
          theme: widget.theme,
          spans: <InlineSpan>[
            ..._labelSpans(label, isIndex),
            _punctuation('$open$close'),
            if (!isLast) _punctuation(','),
          ],
        ),
      );
      return;
    }

    final expanded = widget.controller.isExpanded(path, depth);

    rows.add(
      _JsonRow(
        depth: depth,
        theme: widget.theme,
        expanded: expanded,
        onToggle: () => widget.controller.toggle(path, depth),
        semanticsLabel: widget.strings.jsonNodeSemantics(
          label: label,
          expanded: expanded,
          count: children.length,
          isMap: isMap,
        ),
        spans: <InlineSpan>[
          ..._labelSpans(label, isIndex),
          _punctuation(open),
          if (!expanded) ...<InlineSpan>[
            _punctuation(' … '),
            _punctuation(close),
            _countSpan(children.length, isMap),
            if (!isLast) _punctuation(','),
          ],
        ],
      ),
    );

    if (!expanded) return;

    for (var index = 0; index < children.length; index++) {
      final child = children[index];
      _buildRows(
        rows: rows,
        path: '$path/$index',
        depth: depth + 1,
        label: child.label,
        isIndex: child.isIndex,
        value: child.value,
        isLast: index == children.length - 1,
      );
    }

    rows.add(
      _JsonRow(
        depth: depth,
        theme: widget.theme,
        spans: <InlineSpan>[
          _punctuation(close),
          if (!isLast) _punctuation(','),
        ],
      ),
    );
  }

  static List<_JsonChild>? _childrenOf(Object? value) {
    if (value is Map) {
      return <_JsonChild>[
        for (final entry in value.entries)
          (label: '${entry.key}', isIndex: false, value: entry.value),
      ];
    }
    if (value is List) {
      return <_JsonChild>[
        for (var index = 0; index < value.length; index++)
          (label: '$index', isIndex: true, value: value[index]),
      ];
    }
    return null;
  }

  List<InlineSpan> _labelSpans(String? label, bool isIndex) {
    if (label == null) return const <InlineSpan>[];
    final theme = widget.theme;
    if (isIndex) {
      // An array index reads as a position, not a name, so it is neither quoted
      // nor key-coloured.
      return <InlineSpan>[
        TextSpan(
          text: '$label: ',
          style: TextStyle(color: theme.textFaint, fontSize: 11),
        ),
      ];
    }
    return <InlineSpan>[
      TextSpan(
        text: jsonEncode(label),
        style: TextStyle(
          color: theme.jsonKey,
          fontWeight: FontWeight.w600,
        ),
      ),
      _punctuation(': '),
    ];
  }

  InlineSpan _punctuation(String text) => TextSpan(
        text: text,
        style: TextStyle(color: widget.theme.jsonPunctuation),
      );

  InlineSpan _countSpan(int count, bool isMap) => TextSpan(
        // The leading spaces separate the count from the closing brace.
        text: '  ${widget.strings.jsonCollapsedCount(count, isMap)}',
        style: TextStyle(color: widget.theme.textFaint, fontSize: 11),
      );

  InlineSpan _valueSpan(Object? value) {
    final theme = widget.theme;
    final String text;
    final Color color;

    if (value == null) {
      text = 'null';
      color = theme.jsonNull;
    } else if (value is bool) {
      text = '$value';
      color = theme.jsonBool;
    } else if (value is num) {
      text = '$value';
      color = theme.jsonNumber;
    } else if (value is String) {
      // `jsonEncode` rather than `"$value"`, so quotes, backslashes and newlines
      // inside the string are escaped the way the source document had them.
      text = jsonEncode(value);
      color = theme.jsonString;
    } else {
      text = '$value';
      color = theme.text;
    }

    return TextSpan(text: text, style: TextStyle(color: color));
  }
}

/// One line of the tree.
class _JsonRow extends StatelessWidget {
  const _JsonRow({
    required this.depth,
    required this.theme,
    required this.spans,
    this.onToggle,
    this.expanded = false,
    this.semanticsLabel,
  });

  final int depth;
  final NetworkPanelTheme theme;
  final List<InlineSpan> spans;
  final VoidCallback? onToggle;
  final bool expanded;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final content = Text.rich(
      TextSpan(children: spans),
      style: monospaceStyle.copyWith(
        color: theme.text,
        fontSize: 12,
        height: 1.45,
      ),
    );

    final row = Padding(
      padding: EdgeInsets.only(left: depth * _indentStep, top: 1, bottom: 1),
      child: Row(
        // `start`, not the default `center`: a long value wraps onto several
        // lines, and the arrow belongs beside the first one.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: _twistyWidth,
            child: onToggle == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: AnimatedRotation(
                      turns: expanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Icon(
                        Icons.chevron_right,
                        size: 15,
                        color: theme.textFaint,
                      ),
                    ),
                  ),
          ),
          Expanded(child: content),
        ],
      ),
    );

    if (onToggle == null) return row;

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(
        onTap: onToggle,
        // The whole line toggles, not just the arrow: a 15px target is well under
        // the minimum touch size.
        child: row,
      ),
    );
  }
}
