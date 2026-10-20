import 'package:flutter/material.dart';

import '../core/entry.dart';
import '../i18n/panel_strings.dart';
import 'panel_theme.dart';

/// The active filter selection.
@immutable
class PanelFilters {
  const PanelFilters({this.methods = const <String>{}, this.query = ''});

  /// Empty means "every method".
  final Set<String> methods;

  /// Case-insensitive substring matched against the URL and the method.
  final String query;

  bool get isEmpty => methods.isEmpty && query.trim().isEmpty;

  PanelFilters copyWith({Set<String>? methods, String? query}) => PanelFilters(
        methods: methods ?? this.methods,
        query: query ?? this.query,
      );
}

const PanelFilters emptyFilters = PanelFilters();

/// Distinct methods present in [entries], in a stable order.
///
/// Sorted rather than in first-seen order so the chip row does not reshuffle as
/// traffic arrives.
List<String> collectMethods(List<NetworkEntry> entries) {
  final methods = <String>{
    for (final entry in entries) entry.method.toUpperCase(),
  };
  return methods.toList()..sort();
}

/// Applies [filters] to [entries], preserving order.
///
/// Returns the input list itself when nothing is filtered, so the common path
/// allocates nothing.
List<NetworkEntry> applyFilters(
  List<NetworkEntry> entries,
  PanelFilters filters,
) {
  final query = filters.query.trim().toLowerCase();
  final methods = filters.methods;
  if (methods.isEmpty && query.isEmpty) return entries;

  return <NetworkEntry>[
    for (final entry in entries)
      if ((methods.isEmpty || methods.contains(entry.method.toUpperCase())) &&
          (query.isEmpty ||
              entry.url.toLowerCase().contains(query) ||
              entry.method.toLowerCase().contains(query)))
        entry,
  ];
}

/// Method chips plus a search field.
class FilterBar extends StatefulWidget {
  const FilterBar({
    super.key,
    required this.filters,
    required this.onChanged,
    required this.theme,
    required this.methods,
    required this.strings,
  });

  final PanelFilters filters;
  final ValueChanged<PanelFilters> onChanged;
  final NetworkPanelTheme theme;
  final List<String> methods;
  final PanelStrings strings;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.filters.query);

  @override
  void didUpdateWidget(FilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt an external change (the clear button) but never re-assert the text
    // after a keystroke — doing that moves the cursor to the end on every letter.
    if (widget.filters.query != oldWidget.filters.query &&
        widget.filters.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.filters.query,
        selection: TextSelection.collapsed(
          offset: widget.filters.query.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final strings = widget.strings;
    final filters = widget.filters;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        // Stretch, so the search field spans the row instead of shrinking to the
        // text field's intrinsic width.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.methods.isNotEmpty) ...<Widget>[
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.methods.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (BuildContext context, int index) {
                  final method = widget.methods[index];
                  final selected = filters.methods.contains(method);
                  final tone = theme.methodColor(method);
                  // Material's FilterChip rather than a hand-rolled pill: it
                  // already handles the selected/unselected semantics, the tap
                  // target and the screen-reader announcement.
                  return FilterChip(
                    label: Text(method),
                    selected: selected,
                    onSelected: (_) {
                      final next = Set<String>.of(filters.methods);
                      if (!next.remove(method)) next.add(method);
                      widget.onChanged(filters.copyWith(methods: next));
                    },
                    // The checkmark would sit where the method name is; the fill
                    // colour already says "selected".
                    showCheckmark: false,
                    selectedColor: tone,
                    backgroundColor: theme.card,
                    side: BorderSide(
                      color: selected ? tone : theme.border,
                      width: 0.5,
                    ),
                    shape: const StadiumBorder(),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : theme.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    labelPadding: EdgeInsets.zero,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: 44,
            child: TextField(
              controller: _controller,
              onChanged: (String value) =>
                  widget.onChanged(filters.copyWith(query: value)),
              style: TextStyle(color: theme.text, fontSize: 14),
              cursorColor: theme.accent,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                // Not `isDense`: combined with a fixed height it left the text
                // touching the border and the placeholder looked clipped.
                hintText: strings.searchHint,
                hintStyle: TextStyle(color: theme.textFaint, fontSize: 14),
                prefixIcon: Icon(Icons.search, size: 20, color: theme.textFaint),
                prefixIconConstraints: const BoxConstraints(minWidth: 40),
                suffixIcon: filters.query.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close, size: 18, color: theme.textFaint),
                        tooltip: strings.clearSearch,
                        onPressed: () =>
                            widget.onChanged(filters.copyWith(query: '')),
                        padding: EdgeInsets.zero,
                        // The default 48px tap target is taller than the field.
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                filled: true,
                fillColor: theme.card,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: _border(theme.border, 0.5),
                enabledBorder: _border(theme.border, 0.5),
                focusedBorder: _border(theme.accent, 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static OutlineInputBorder _border(Color color, double width) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );
}
