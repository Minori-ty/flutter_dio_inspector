import 'package:flutter/material.dart';

import '../core/curl.dart';
import '../core/entry.dart';
import '../core/format.dart';
import '../i18n/panel_language.dart';
import '../i18n/panel_strings.dart';
import '../store/network_store.dart';
import 'json_tree.dart';
import 'panel_theme.dart';
import 'primitives.dart';
import 'toast.dart';

/// Full detail for a single captured request.
///
/// Reads the entry out of the store on every rebuild rather than holding a
/// snapshot, so a request that is still in flight updates here as it completes.
class NetworkEntryDetailPage extends StatefulWidget {
  const NetworkEntryDetailPage({
    super.key,
    required this.store,
    required this.entryId,
    this.languageController,
  });

  final NetworkStore store;
  final String entryId;

  /// Language of the panel. Optional, and created on demand when omitted, so the
  /// page can be pushed directly without a [DioNetworkPanel] above it.
  final PanelLanguageController? languageController;

  @override
  State<NetworkEntryDetailPage> createState() => _NetworkEntryDetailPageState();
}

class _NetworkEntryDetailPageState extends State<NetworkEntryDetailPage>
    with ToastStateMixin<NetworkEntryDetailPage> {
  /// One controller per body.
  ///
  /// They are not shared: node paths are built from child indices, so a request
  /// body and a response body with the same shape would collide, and a shared
  /// controller would make one section's expand-all reach into the other.
  final JsonTreeController _requestJson = JsonTreeController();
  final JsonTreeController _responseJson = JsonTreeController();

  late final PanelLanguageController _language =
      widget.languageController ?? PanelLanguageController();

  /// A controller created here has to be disposed here; one handed in belongs to
  /// whoever passed it.
  late final bool _ownsLanguage = widget.languageController == null;

  @override
  void dispose() {
    _requestJson.dispose();
    _responseJson.dispose();
    if (_ownsLanguage) _language.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = NetworkPanelTheme.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[widget.store, _language]),
      builder: (BuildContext context, Widget? _) {
        final strings = PanelStrings.of(_language.language);
        final entry = widget.store.byId(widget.entryId);
        return Scaffold(
          backgroundColor: theme.background,
          appBar: AppBar(
            backgroundColor: theme.card,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            foregroundColor: theme.text,
            titleSpacing: 0,
            title: entry == null
                ? Text(
                    strings.detailTitle,
                    style: TextStyle(color: theme.text, fontSize: 16),
                  )
                : _DetailTitle(entry: entry, theme: theme, strings: strings),
            actions: <Widget>[
              if (entry != null)
                IconAction(
                  icon: Icons.terminal,
                  label: strings.copyCurl,
                  theme: theme,
                  onPressed: () => copyWithFeedback(
                    toCurlCommand(entry),
                    'cURL',
                    strings,
                    showToast,
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),
          body: Stack(
            children: <Widget>[
              if (entry == null)
                EmptyState(theme: theme, message: strings.entryEvicted)
              else
                _DetailBody(
                  entry: entry,
                  theme: theme,
                  strings: strings,
                  requestJson: _requestJson,
                  responseJson: _responseJson,
                  onCopy: (String text, String label) =>
                      copyWithFeedback(text, label, strings, showToast),
                ),
              ToastOverlay(message: toastMessage, theme: theme),
            ],
          ),
        );
      },
    );
  }
}

class _DetailTitle extends StatelessWidget {
  const _DetailTitle({
    required this.entry,
    required this.theme,
    required this.strings,
  });

  final NetworkEntry entry;
  final NetworkPanelTheme theme;
  final PanelStrings strings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        MethodBadge(method: entry.method, theme: theme),
        const SizedBox(width: 10),
        Text(
          strings.statusLabel(entry),
          style: TextStyle(
            color: theme.stateColor(entry),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            entry.displayOrigin,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.textMuted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.entry,
    required this.theme,
    required this.strings,
    required this.requestJson,
    required this.responseJson,
    required this.onCopy,
  });

  final NetworkEntry entry;
  final NetworkPanelTheme theme;
  final PanelStrings strings;
  final JsonTreeController requestJson;
  final JsonTreeController responseJson;
  final void Function(String text, String label) onCopy;

  @override
  Widget build(BuildContext context) {
    final requestHeaders = _formatHeaders(entry.requestHeaders);
    final responseHeaders = _formatHeaders(entry.responseHeaders);
    final requestBody = entry.requestBody;
    final responseBody = entry.responseBody;

    final overview = <Widget>[
      _CopyableRow(
        label: 'URL',
        value: entry.url,
        theme: theme,
        strings: strings,
        mono: true,
        onCopy: () => onCopy(entry.url, 'URL'),
      ),
      KeyValueRow(
        label: strings.method,
        value: entry.method.toUpperCase(),
        theme: theme,
      ),
      KeyValueRow(
        label: strings.startedAt,
        value: formatClock(entry.startedAt),
        theme: theme,
        mono: true,
      ),
      KeyValueRow(
        label: strings.duration,
        value: formatDuration(entry.duration),
        theme: theme,
        mono: true,
      ),
      KeyValueRow(
        label: strings.status,
        value: _statusDescription(entry),
        theme: theme,
      ),
      if (entry.failureLabel != null)
        KeyValueRow(
          label: strings.failureReason,
          value: strings.failureWithCause(
            strings.failureLabel(entry.failureKind),
            entry.failureLabel!,
          ),
          theme: theme,
        ),
      if (responseBody != null)
        KeyValueRow(
          label: strings.responseSize,
          value: formatBytes(responseBody.byteLength),
          theme: theme,
          mono: true,
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: <Widget>[
        _Section(
          key: const ValueKey<String>('overview'),
          title: strings.overview,
          theme: theme,
          strings: strings,
          child: Rows(theme: theme, children: overview),
        ),
        if (entry.state == NetworkState.pending)
          _PendingNote(theme: theme, strings: strings),
        if (entry.errorMessage != null)
          _Section(
            key: const ValueKey<String>('error'),
            title: strings.sectionError,
            theme: theme,
            strings: strings,
            child: MonoBlock(
              text: entry.errorMessage!,
              theme: theme,
              placeholder: strings.emptyBody,
            ),
          ),
        _Section(
          key: const ValueKey<String>('request-headers'),
          title: strings.requestHeaders,
          // Folded by default: on a phone the headers push the bodies below the
          // fold, and the bodies are what you opened the request for. The count in
          // the header still says how much is inside.
          subtitle: _headerCount(entry.requestHeaders),
          collapsible: true,
          initiallyExpanded: false,
          theme: theme,
          strings: strings,
          copyLabel: strings.requestHeaders,
          copyText: requestHeaders,
          onCopy: onCopy,
          child: requestHeaders.isEmpty
              ? MonoBlock(text: '', theme: theme, placeholder: strings.none)
              : Rows(theme: theme, children: _headerRows(entry.requestHeaders)),
        ),
        if (requestBody != null)
          _Section(
            key: const ValueKey<String>('request-body'),
            title: strings.requestBody,
            theme: theme,
            strings: strings,
            subtitle: _bodySubtitle(requestBody),
            extraActions: _jsonActions(requestBody, requestJson),
            copyLabel: strings.requestBody,
            copyText: requestBody.preview,
            onCopy: onCopy,
            child: _bodyChild(requestBody, requestJson),
          ),
        if (entry.responseHeaders.isNotEmpty)
          _Section(
            key: const ValueKey<String>('response-headers'),
            title: strings.responseHeaders,
            subtitle: _headerCount(entry.responseHeaders),
            collapsible: true,
            initiallyExpanded: false,
            theme: theme,
            strings: strings,
            copyLabel: strings.responseHeaders,
            copyText: responseHeaders,
            onCopy: onCopy,
            child: Rows(theme: theme, children: _headerRows(entry.responseHeaders)),
          ),
        if (responseBody != null)
          _Section(
            key: const ValueKey<String>('response-body'),
            title: strings.responseBody,
            theme: theme,
            strings: strings,
            subtitle: _bodySubtitle(responseBody),
            extraActions: _jsonActions(responseBody, responseJson),
            copyLabel: strings.responseBody,
            copyText: responseBody.preview,
            onCopy: onCopy,
            child: _bodyChild(responseBody, responseJson),
          ),
      ],
    );
  }

  String _headerCount(Map<String, String> headers) =>
      strings.itemCount(headers.length);

  /// The tree for a JSON body, plain text for anything else.
  ///
  /// The kind check is a cheap sniff; [JsonTreeView] itself falls back to plain
  /// text when the document does not parse — which is the normal outcome for a
  /// body that was truncated at the capture limit.
  Widget _bodyChild(BodySnapshot body, JsonTreeController controller) {
    if (_isJsonBody(body)) {
      return JsonTreeView(
        source: body.preview,
        theme: theme,
        controller: controller,
        strings: strings,
      );
    }
    return MonoBlock(
      text: body.preview,
      theme: theme,
      placeholder: _bodyPlaceholder(body),
    );
  }

  List<Widget> _jsonActions(BodySnapshot body, JsonTreeController controller) {
    if (!_isJsonBody(body)) return const <Widget>[];
    return <Widget>[
      IconAction(
        icon: Icons.unfold_more,
        label: strings.expandAll,
        theme: theme,
        size: 18,
        onPressed: controller.expandAll,
      ),
      IconAction(
        icon: Icons.unfold_less,
        label: strings.collapseAll,
        theme: theme,
        size: 18,
        onPressed: controller.collapseAll,
      ),
    ];
  }

  static bool _isJsonBody(BodySnapshot body) =>
      body.kind == BodyKind.json && body.preview.isNotEmpty;

  List<Widget> _headerRows(Map<String, String> headers) {
    final keys = headers.keys.toList()..sort();
    return <Widget>[
      for (final key in keys)
        HeaderRow(name: key, value: headers[key]!, theme: theme),
    ];
  }

  static String _formatHeaders(Map<String, String> headers) {
    final keys = headers.keys.toList()..sort();
    return <String>[
      for (final key in keys) '$key: ${headers[key]}',
    ].join('\n');
  }

  String _statusDescription(NetworkEntry value) {
    final status = value.statusCode;
    if (status == null) return strings.statusLabel(value);
    final reason = value.statusMessage;
    if (reason == null || reason.isEmpty) return '$status';
    return '$status $reason';
  }

  String? _bodySubtitle(BodySnapshot body) {
    final parts = <String>[
      strings.bodyKindLabel(body.kind),
      formatBytes(body.byteLength),
    ];
    if (body.truncated) parts.add(strings.truncated);
    return parts.join(' · ');
  }

  String _bodyPlaceholder(BodySnapshot body) {
    switch (body.kind) {
      case BodyKind.stream:
        return strings.streamPlaceholder;
      case BodyKind.binary:
        return strings.binaryPlaceholder(body.byteLength);
      case BodyKind.empty:
      case BodyKind.json:
      case BodyKind.text:
      case BodyKind.form:
        return strings.emptyBody;
    }
  }
}

/// A [KeyValueRow] whose whole row copies, with a trailing glyph saying so.
class _CopyableRow extends StatelessWidget {
  const _CopyableRow({
    required this.label,
    required this.value,
    required this.theme,
    required this.strings,
    required this.onCopy,
    this.mono = false,
  });

  final String label;
  final String value;
  final NetworkPanelTheme theme;
  final PanelStrings strings;
  final VoidCallback onCopy;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onCopy,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 5, 4, 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 68,
              child: Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  label,
                  style: TextStyle(color: theme.textMuted, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  value,
                  style: (mono ? monospaceStyle : const TextStyle()).copyWith(
                    color: theme.text,
                    fontSize: mono ? 12 : 13,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            IconAction(
              icon: Icons.copy_outlined,
              label: strings.copyAction(label),
              theme: theme,
              size: 16,
              onPressed: onCopy,
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains the one case the panel cannot observe.
///
/// dio completes a `handler.reject()` from a request interceptor with a *value*
/// (`InterceptorResultType.reject`) rather than a Future error, and its error
/// handlers are attached with `catchError`. So when `callFollowingErrorInterceptor`
/// is left at its `false` default, no `onError` runs anywhere, and there is no hook
/// that could record the outcome. Saying so beats showing a spinner that will never
/// stop.
class _PendingNote extends StatelessWidget {
  const _PendingNote({required this.theme, required this.strings});

  final NetworkPanelTheme theme;
  final PanelStrings strings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.border, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.info_outline, size: 16, color: theme.textFaint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.pendingNote,
                style: TextStyle(
                  color: theme.textMuted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled card with an optional copy affordance in its header.
///
/// Stateful only because a collapsible section remembers whether it is open.
/// Sections carry keys at the call site: the list is built conditionally (an error
/// section appears when a pending request fails), and without keys a section's
/// state would follow its index rather than its identity.
class _Section extends StatefulWidget {
  const _Section({
    super.key,
    required this.title,
    required this.theme,
    required this.strings,
    required this.child,
    this.subtitle,
    this.copyLabel,
    this.copyText,
    this.onCopy,
    this.extraActions = const <Widget>[],
    this.collapsible = false,
    this.initiallyExpanded = true,
  });

  final String title;
  final NetworkPanelTheme theme;
  final PanelStrings strings;
  final Widget child;
  final String? subtitle;
  final String? copyLabel;
  final String? copyText;
  final void Function(String text, String label)? onCopy;

  /// Actions shown before the copy button — the JSON tree's expand/collapse.
  final List<Widget> extraActions;

  /// Whether the header can be tapped to fold the card away.
  final bool collapsible;

  /// Only meaningful with [collapsible]. The headers start folded; the bodies,
  /// which are the reason you opened the request, start open.
  final bool initiallyExpanded;

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _expanded = !widget.collapsible || widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final label = widget.copyLabel;
    final text = widget.copyText;
    final canCopy = label != null &&
        text != null &&
        text.isNotEmpty &&
        widget.onCopy != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        // Stretch so the card always spans the page width. With a loose
        // cross-axis constraint the card would size to its widest child, which
        // happens to work today only because every section contains something
        // full-width.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(
            title: widget.subtitle == null
                ? widget.title
                : '${widget.title} · ${widget.subtitle}',
            theme: theme,
            expanded: _expanded,
            onTap: widget.collapsible
                ? () => setState(() => _expanded = !_expanded)
                : null,
            // The copy button stays visible while folded — copying a header block
            // is often why you came, and unfolding it first would be busywork.
            trailing: (canCopy || widget.extraActions.isNotEmpty)
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ...widget.extraActions,
                      if (canCopy)
                        IconAction(
                          icon: Icons.copy_outlined,
                          label: widget.strings.copyAction(label),
                          theme: theme,
                          size: 16,
                          onPressed: () => widget.onCopy!(text, label),
                        ),
                    ],
                  )
                : null,
          ),
          if (_expanded) SectionCard(theme: theme, child: widget.child),
        ],
      ),
    );
  }
}
