import 'package:flutter/material.dart';

import '../core/unseen.dart';
import '../i18n/panel_language.dart';
import '../i18n/panel_strings.dart';
import '../store/network_store.dart';
import 'float_ball.dart';
import 'panel_page.dart';
import 'panel_theme.dart';

/// Renders [child] with a draggable floating ball on top.
///
/// Place it in `MaterialApp.builder` so the ball floats above every route:
///
/// ```dart
/// final navigatorKey = GlobalKey<NavigatorState>();
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
///
/// [navigatorKey] is required *for that placement* and not as a general rule.
/// `MaterialApp.builder` wraps the `Navigator`, so its context has no `Navigator`
/// ancestor to push onto — the key is how the panel reaches the one the app
/// created. If the panel is instead placed below a `Navigator` (inside a `Stack`
/// on a page, say), the key can be omitted and the nearest one is used.
class DioNetworkPanel extends StatefulWidget {
  const DioNetworkPanel({
    super.key,
    required this.store,
    required this.child,
    this.navigatorKey,
    this.hideBall = false,
    this.ballSize = 54,
    this.languageController,
  });

  final NetworkStore store;
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Keep capturing, but hide the ball. Useful for a release build, or when the
  /// panel is opened from somewhere else in the app.
  final bool hideBall;

  final double ballSize;

  /// Language of the panel, shared by the ball and every page it pushes.
  ///
  /// Omit it and the panel creates one that starts in English; the switch in the
  /// panel header then writes to that private instance. Pass your own when you
  /// want to start in Chinese, keep the choice across a restart, or open
  /// [NetworkPanelPage] yourself and have it agree with the ball.
  final PanelLanguageController? languageController;

  @override
  State<DioNetworkPanel> createState() => _DioNetworkPanelState();
}

class _DioNetworkPanelState extends State<DioNetworkPanel> {
  /// Id of the newest entry at the moment the panel was last dismissed.
  ///
  /// Everything newer than it is "new", driving both the ball badge and the `NEW`
  /// marker on each row. It moves on *close*, never on open.
  String? _seenId;

  /// Where the user dragged the ball. Null until they do.
  Offset? _ballOffset;

  /// Whether the panel route is on screen.
  ///
  /// The ball lives in this widget, which `MaterialApp.builder` places *above*
  /// the `Navigator` — so a pushed route is painted underneath it and the ball
  /// would float on top of the panel it opened. Hiding it for the duration is the
  /// only way to get it out of the way.
  bool _panelOpen = false;

  late final PanelLanguageController _language =
      widget.languageController ?? PanelLanguageController();

  /// A controller created here has to be disposed here; one handed in belongs to
  /// whoever passed it.
  late final bool _ownsLanguage = widget.languageController == null;

  PanelStrings get _strings => PanelStrings.of(_language.language);

  @override
  void dispose() {
    if (_ownsLanguage) _language.dispose();
    super.dispose();
  }

  static const double _margin = 8;
  static const double _bottomInset = 96;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[widget.store, _language]),
      builder: (BuildContext context, Widget? _) {
        if (widget.hideBall || _panelOpen) return widget.child;

        final theme = NetworkPanelTheme.of(context);
        final unseen = countUnseen(widget.store.entries, _seenId);

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Stack(
              children: <Widget>[
                widget.child,
                _ball(theme, unseen, constraints),
              ],
            );
          },
        );
      },
    );
  }

  Widget _ball(
    NetworkPanelTheme theme,
    int unseen,
    BoxConstraints constraints,
  ) {
    final size = widget.ballSize;
    final maxX = _clamp(constraints.maxWidth - size - _margin, _margin, double.infinity);
    final maxY = _clamp(constraints.maxHeight - size - _margin, _margin, double.infinity);

    // Default to the lower right, a little clear of the bottom edge. A stored
    // offset is re-clamped every build, so a rotation or a window resize cannot
    // leave the ball off screen.
    final stored = _ballOffset;
    final offset = stored == null
        ? Offset(maxX, _clamp(maxY - _bottomInset, _margin, maxY))
        : Offset(
            _clamp(stored.dx, _margin, maxX),
            _clamp(stored.dy, _margin, maxY),
          );

    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Both handlers read `_ballOffset` off the state rather than the `offset`
        // captured by this build. A gesture can deliver its final move and its end
        // in the same frame, so a closure captured at build time can be one drag
        // behind — which made a fast flick snap back to where it started.
        onPanUpdate: (DragUpdateDetails details) {
          final current = _ballOffset ?? offset;
          setState(() {
            _ballOffset = Offset(
              _clamp(current.dx + details.delta.dx, _margin, maxX),
              _clamp(current.dy + details.delta.dy, _margin, maxY),
            );
          });
        },
        onPanEnd: (DragEndDetails _) {
          // Snap to the nearer edge: parked in the middle, the ball covers the
          // content it is meant to be observing.
          final current = _ballOffset ?? offset;
          final snappedLeft = current.dx + size / 2 < constraints.maxWidth / 2;
          setState(() {
            _ballOffset = Offset(snappedLeft ? _margin : maxX, current.dy);
          });
        },
        child: FloatBall(
          theme: theme,
          badge: unseen,
          size: size,
          strings: _strings,
          onTap: _openPanel,
        ),
      ),
    );
  }

  Future<void> _openPanel() async {
    final navigator = widget.navigatorKey?.currentState ??
        Navigator.maybeOf(context, rootNavigator: true);

    if (navigator == null) {
      assert(() {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('DioNetworkPanel could not find a Navigator.'),
          ErrorDescription(
            'Placed in MaterialApp.builder, the panel sits above the Navigator and '
            'cannot reach it. Pass the same navigatorKey you gave MaterialApp, or '
            'place the panel below a Navigator.',
          ),
        ]);
      }());
      return;
    }

    // Hidden before the push rather than after, so it is gone for the whole
    // transition instead of floating over the incoming panel for 300ms.
    setState(() => _panelOpen = true);

    await navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => NetworkPanelPage(
          store: widget.store,
          seenId: _seenId,
          languageController: _language,
        ),
      ),
    );
    if (!mounted) return;

    // Dismissing the panel is what marks everything as seen. Doing it here rather
    // than on open is the whole point: the NEW markers have to survive the visit,
    // or they would clear at the exact moment you opened the panel to find them.
    final entries = widget.store.entries;
    setState(() {
      _panelOpen = false;
      if (entries.isNotEmpty) _seenId = entries.first.id;
    });
  }
}

double _clamp(double value, double min, double max) {
  if (max < min) return min;
  if (value < min) return min;
  if (value > max) return max;
  return value;
}
