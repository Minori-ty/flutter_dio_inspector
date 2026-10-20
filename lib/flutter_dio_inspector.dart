/// An in-app network panel for Dio.
///
/// A draggable floating ball with an unread badge, and a full-screen inspector
/// for requests, responses, headers, bodies and cURL export.
///
/// ```dart
/// final store = NetworkStore();
/// final navigatorKey = GlobalKey<NavigatorState>();
///
/// final dio = Dio()
///   ..interceptors.add(DioNetworkPanelInterceptor(store: store));
///
/// MaterialApp(
///   navigatorKey: navigatorKey,
///   builder: (context, child) => DioNetworkPanel(
///     store: store,
///     navigatorKey: navigatorKey,
///     child: child ?? const SizedBox.shrink(),
///   ),
///   home: const HomePage(),
/// );
/// ```
library;

export 'src/core/buffer.dart' show NetworkEntryBuffer;
export 'src/core/config.dart' show NetworkIgnorePredicate, NetworkPanelConfig;
export 'src/core/console_log.dart' show formatConsoleLog;
export 'src/core/curl.dart' show toCurlCommand;
export 'src/core/entry.dart'
    show BodyKind, BodySnapshot, NetworkEntry, NetworkFailure, NetworkState;
export 'src/core/format.dart' show formatBytes, formatClock, formatDuration;
export 'src/core/json_preview.dart'
    show JsonDecodeResult, decodeJson, isJsonContainer, jsonChildCount;
export 'src/core/serializer.dart'
    show
        defaultRedactedHeaders,
        redactedPlaceholder,
        sensitiveHeaders,
        utf8ByteLength;
export 'src/core/unseen.dart' show countUnseen, unseenIds;
export 'src/intercept/dio_network_panel_interceptor.dart'
    show DioNetworkPanelInterceptor;
export 'src/i18n/panel_language.dart'
    show PanelLanguage, PanelLanguageController;
export 'src/i18n/panel_strings.dart' show PanelStrings;
export 'src/store/network_store.dart' show NetworkStore;
export 'src/ui/dio_network_panel.dart' show DioNetworkPanel;
export 'src/ui/entry_detail_page.dart' show NetworkEntryDetailPage;
export 'src/ui/entry_tile.dart' show EntryTile;
export 'src/ui/float_ball.dart' show FloatBall;
export 'src/ui/json_tree.dart' show JsonTreeController, JsonTreeView;
export 'src/ui/panel_theme.dart'
    show NetworkPanelTheme, bodyKindLabel, failureLabel, monospaceStyle;
export 'src/ui/panel_page.dart' show NetworkPanelPage;
