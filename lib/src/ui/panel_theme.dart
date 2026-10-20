import 'package:flutter/material.dart';

import '../core/entry.dart';
import '../i18n/panel_strings.dart';

/// Colours for the panel.
///
/// The panel carries its own palette rather than inheriting the host app's
/// `ColorScheme`. A debug overlay that changes colour with the app's branding is
/// harder to read across projects, and the method/status colours need to mean the
/// same thing everywhere.
@immutable
class NetworkPanelTheme {
  const NetworkPanelTheme({
    required this.brightness,
    required this.background,
    required this.card,
    required this.pressed,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.onAccent,
    required this.success,
    required this.danger,
    required this.warning,
    required this.jsonKey,
    required this.jsonString,
    required this.jsonNumber,
    required this.jsonBool,
    required this.jsonNull,
    required this.jsonPunctuation,
  });

  final Brightness brightness;

  /// The grouped-list backdrop the cards sit on.
  final Color background;

  /// A card, and the surface for rows inside one.
  final Color card;

  /// Fill for a pressed card or chip.
  final Color pressed;

  final Color border;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color accent;

  /// Text/icon colour on top of [accent].
  final Color onAccent;

  final Color success;
  final Color danger;
  final Color warning;

  /// JSON syntax colours.
  ///
  /// Keys get their own hue rather than sharing the string colour: in a tree view
  /// the key and the value sit on the same line, and telling them apart at a
  /// glance is the whole point of the highlighting.
  final Color jsonKey;
  final Color jsonString;
  final Color jsonNumber;
  final Color jsonBool;
  final Color jsonNull;
  final Color jsonPunctuation;

  static const NetworkPanelTheme light = NetworkPanelTheme(
    brightness: Brightness.light,
    background: Color(0xFFF2F2F7),
    card: Color(0xFFFFFFFF),
    pressed: Color(0xFFE5E5EA),
    border: Color(0xFFE5E5EA),
    text: Color(0xFF1C1C1E),
    textMuted: Color(0xFF7C7C80),
    textFaint: Color(0xFFAEAEB2),
    accent: Color(0xFF0A84FF),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF34C759),
    danger: Color(0xFFFF3B30),
    warning: Color(0xFFFF9500),
    jsonKey: Color(0xFF7C3AED),
    jsonString: Color(0xFF15803D),
    jsonNumber: Color(0xFFC2410C),
    jsonBool: Color(0xFF1D4ED8),
    jsonNull: Color(0xFF9CA3AF),
    jsonPunctuation: Color(0xFF6B7280),
  );

  static const NetworkPanelTheme dark = NetworkPanelTheme(
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    card: Color(0xFF1C1C1E),
    pressed: Color(0xFF2C2C2E),
    border: Color(0xFF38383A),
    text: Color(0xFFFFFFFF),
    textMuted: Color(0xFF98989F),
    textFaint: Color(0xFF636366),
    accent: Color(0xFF0A84FF),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF30D158),
    danger: Color(0xFFFF453A),
    warning: Color(0xFFFFD60A),
    jsonKey: Color(0xFFC4A6FF),
    jsonString: Color(0xFF6EE7A0),
    jsonNumber: Color(0xFFFDBA74),
    jsonBool: Color(0xFF93C5FD),
    jsonNull: Color(0xFF6B7280),
    jsonPunctuation: Color(0xFF9CA3AF),
  );

  static NetworkPanelTheme resolve(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static NetworkPanelTheme of(BuildContext context) =>
      resolve(Theme.of(context).brightness);

  /// Colour per HTTP method, so a method is recognisable at a glance without
  /// reading it.
  Color methodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return const Color(0xFF0A84FF);
      case 'POST':
        return const Color(0xFF8B5CF6);
      case 'PUT':
        return const Color(0xFFF97316);
      case 'PATCH':
        return const Color(0xFFA16207);
      case 'DELETE':
        return const Color(0xFFEF4444);
      case 'HEAD':
      case 'OPTIONS':
        return const Color(0xFF0D9488);
      default:
        return const Color(0xFF6B7280);
    }
  }

  /// Colour for a response status code.
  Color statusColor(int? status) {
    if (status == null) return textFaint;
    if (status < 300) return success;
    if (status < 400) return accent;
    if (status < 500) return warning;
    return danger;
  }

  /// Colour for the row's status slot, which is driven by the outcome rather
  /// than only the status code — a timeout has no status at all.
  Color stateColor(NetworkEntry entry) {
    switch (entry.state) {
      case NetworkState.pending:
        return textFaint;
      case NetworkState.success:
        return statusColor(entry.statusCode);
      case NetworkState.timeout:
        return warning;
      case NetworkState.error:
      case NetworkState.canceled:
        return danger;
    }
  }

  /// The right-hand label for a row, in Chinese.
  ///
  /// Text lives in [PanelStrings] now, so this is a Chinese-only shortcut kept
  /// for callers of the 0.1 API. The panel itself asks `PanelStrings` for the
  /// label, which is what makes it translatable.
  String statusLabel(NetworkEntry entry) => PanelStrings.zh.statusLabel(entry);
}

/// Human-readable label for a failure reason, in Chinese.
///
/// See [PanelStrings.failureLabel] for the localised version.
String failureLabel(NetworkFailure? failure) =>
    PanelStrings.zh.failureLabel(failure);

/// Human-readable label for a captured body kind, in Chinese.
///
/// See [PanelStrings.bodyKindLabel] for the localised version.
String bodyKindLabel(BodyKind kind) => PanelStrings.zh.bodyKindLabel(kind);

/// Monospace style for bodies, headers and the URL.
///
/// Android ships a `monospace` family; iOS does not, so `Menlo` and `Courier` are
/// listed as fallbacks. Without them iOS renders these in the default
/// proportional font, which is noticeably worse for JSON and hex.
const TextStyle monospaceStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: <String>['Menlo', 'Courier New', 'Courier'],
);
