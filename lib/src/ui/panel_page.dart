import 'package:flutter/material.dart';

import '../core/entry.dart';
import '../core/unseen.dart';
import '../i18n/panel_language.dart';
import '../i18n/panel_strings.dart';
import '../store/network_store.dart';
import 'entry_detail_page.dart';
import 'entry_tile.dart';
import 'filter_bar.dart';
import 'panel_theme.dart';
import 'primitives.dart';
import 'toast.dart';

/// The request list.
///
/// Pushed as a full-screen route, so the system back gesture unwinds it for free,
/// and pushing the detail on top of it means back goes detail → list → app
/// without any custom handling.
class NetworkPanelPage extends StatefulWidget {
  const NetworkPanelPage({
    super.key,
    required this.store,
    required this.seenId,
    this.languageController,
  });

  final NetworkStore store;

  /// Everything newer than this id is marked `NEW`.
  ///
  /// Captured when the panel opens rather than kept live: the watermark is meant
  /// to move when the panel is *dismissed*, so the markers stay put for the whole
  /// session — otherwise they would vanish at the moment you opened the panel to
  /// look for them.
  final String? seenId;

  /// Language of the panel, and the thing the header's switch writes to.
  ///
  /// Optional so the page still works when pushed directly rather than through
  /// `DioNetworkPanel`: it then owns a controller of its own, starting in
  /// English. Pass the same instance to the panel widget if you want the ball and
  /// the pages to agree.
  final PanelLanguageController? languageController;

  @override
  State<NetworkPanelPage> createState() => _NetworkPanelPageState();
}

class _NetworkPanelPageState extends State<NetworkPanelPage>
    with ToastStateMixin<NetworkPanelPage> {
  /// Ids whose detail was opened during this visit.
  ///
  /// Opening a row is an explicit "I have seen this", so its marker has to clear
  /// then and there. The watermark cannot do it — that only moves when the whole
  /// panel closes. Kept local because it describes this visit to the list, not the
  /// captured request.
  final Set<String> _openedIds = <String>{};

  PanelFilters _filters = emptyFilters;

  late final PanelLanguageController _language =
      widget.languageController ?? PanelLanguageController();

  /// A controller created here has to be disposed here; one handed in belongs to
  /// whoever passed it.
  late final bool _ownsLanguage = widget.languageController == null;

  @override
  void dispose() {
    if (_ownsLanguage) _language.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = NetworkPanelTheme.of(context);

    return ListenableBuilder(
      // The language is part of what this page renders, so a switch rebuilds it
      // just like new traffic does.
      listenable: Listenable.merge(<Listenable>[widget.store, _language]),
      builder: (BuildContext context, Widget? _) {
        final strings = PanelStrings.of(_language.language);
        final entries = widget.store.entries;
        final fresh = unseenIds(entries, widget.seenId);
        final unseen = _openedIds.isEmpty
            ? fresh
            : (Set<String>.of(fresh)..removeAll(_openedIds));
        final shown = applyFilters(entries, _filters);
        final failed =
            entries.where((NetworkEntry entry) => entry.state.isFailure).length;

        return Scaffold(
          backgroundColor: theme.background,
          appBar: AppBar(
            backgroundColor: theme.card,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            foregroundColor: theme.text,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  strings.panelTitle,
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _summary(shown.length, entries.length, failed, strings),
                  // The header carries three actions now, so the summary has to
                  // give way rather than wrap under a 56dp toolbar.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: theme.textMuted, fontSize: 11),
                ),
              ],
            ),
            actions: <Widget>[
              _LanguageSwitch(
                strings: strings,
                theme: theme,
                onPressed: _language.toggle,
              ),
              TextButton(
                onPressed: entries.isEmpty ? null : widget.store.clear,
                style: TextButton.styleFrom(foregroundColor: theme.accent),
                child: Text(strings.clear),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(foregroundColor: theme.accent),
                child: Text(strings.close),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Stack(
            children: <Widget>[
              Column(
                // Stretch so the filter bar and the list both span the width.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (entries.isNotEmpty)
                    FilterBar(
                      filters: _filters,
                      onChanged: (PanelFilters next) =>
                          setState(() => _filters = next),
                      theme: theme,
                      methods: collectMethods(entries),
                      strings: strings,
                    ),
                  Expanded(
                    child: shown.isEmpty
                        ? EmptyState(
                            theme: theme,
                            message: entries.isEmpty
                                ? strings.emptyNoTraffic
                                : strings.emptyFiltered,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                            itemCount: shown.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (BuildContext context, int index) {
                              final entry = shown[index];
                              return EntryTile(
                                entry: entry,
                                theme: theme,
                                isNew: unseen.contains(entry.id),
                                strings: strings,
                                onTap: () => _openDetail(entry.id),
                              );
                            },
                          ),
                  ),
                ],
              ),
              ToastOverlay(message: toastMessage, theme: theme),
            ],
          ),
        );
      },
    );
  }

  String _summary(int shown, int total, int failed, PanelStrings strings) {
    final parts = <String>['$shown/$total'];
    if (failed > 0) parts.add(strings.failedCount(failed));
    final evicted = widget.store.evictedCount;
    if (evicted > 0) parts.add(strings.evictedCount(evicted));
    return parts.join(' · ');
  }

  /// Opening a row both navigates and marks it seen.
  void _openDetail(String id) {
    setState(() => _openedIds.add(id));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => NetworkEntryDetailPage(
          store: widget.store,
          entryId: id,
          languageController: _language,
        ),
      ),
    );
  }
}

/// The header's language button.
///
/// It shows the language a tap will switch *to* (`EN` while in Chinese), so the
/// button states the outcome instead of naming the current state — a button
/// labelled `中文` inside a Chinese panel reads as "already Chinese, nothing to
/// do here".
class _LanguageSwitch extends StatelessWidget {
  const _LanguageSwitch({
    required this.strings,
    required this.theme,
    required this.onPressed,
  });

  final PanelStrings strings;
  final NetworkPanelTheme theme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: strings.switchLanguageHint,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: theme.accent,
          // Compact: the header already carries two text actions, and this label
          // is only two glyphs. The default 64dp minimum would squeeze the title.
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        child: Text(strings.switchLanguageLabel),
      ),
    );
  }
}
