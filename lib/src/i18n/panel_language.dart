import 'package:flutter/foundation.dart';

/// The panel's own UI language.
///
/// Deliberately independent of `MaterialApp.locale`: a debug overlay is read by
/// the developer, not by the end user, so it should not follow the app's
/// localisation — and the panel must keep working in an app that never
/// configured `flutter_localizations` at all.
enum PanelLanguage {
  zh,
  en;

  /// The language a toggle should switch to.
  PanelLanguage get other =>
      this == PanelLanguage.zh ? PanelLanguage.en : PanelLanguage.zh;

  /// The language for a stored code, falling back to [fallback].
  ///
  /// Tolerant on purpose. The code comes from wherever the host app keeps its
  /// settings, so it can be missing, empty, or written by a newer version that
  /// knows a language this one does not — none of which should stop the panel
  /// from opening.
  ///
  /// Writes are the other direction and need no helper: `language.name` is the
  /// code.
  static PanelLanguage fromCode(
    String? code, {
    PanelLanguage fallback = PanelLanguage.en,
  }) {
    for (final language in values) {
      if (language.name == code) return language;
    }
    return fallback;
  }
}

/// Holds the panel's language and notifies whoever is showing it.
///
/// One controller drives the whole panel — list, detail and the ball — so
/// flipping the language in the list is reflected everywhere at once. Pass the
/// same instance to [DioNetworkPanel] and to any page you push yourself; leave
/// it out and each entry point creates its own, starting in English.
class PanelLanguageController extends ChangeNotifier {
  /// English unless told otherwise.
  ///
  /// Not read from the platform on purpose. The panel's language is a property of
  /// the team reading it, not of the device it happens to run on — a Chinese app
  /// on an English phone still wants its debug overlay in the language its
  /// developers think in, and either way the switch in the header is one tap
  /// away. Pass `initial: PanelLanguage.zh` to start in Chinese.
  PanelLanguageController({
    PanelLanguage initial = PanelLanguage.en,
    this.onChanged,
  }) : _language = initial;

  /// Called after [language] changes — the slot for persistence.
  ///
  /// The package deliberately has no storage dependency, so saving the choice is
  /// the host app's business: hand it a callback and the language survives a
  /// restart, leave it out and the choice lasts as long as this controller does.
  /// An app without its own settings simply omits it.
  ///
  /// The callback runs *after* listeners have been notified, and anything it
  /// throws is swallowed and reported through `debugPrint`: a failed settings
  /// write must not break the switch that triggered it.
  final void Function(PanelLanguage language)? onChanged;

  PanelLanguage _language;

  PanelLanguage get language => _language;

  set language(PanelLanguage value) {
    if (value == _language) return;
    _language = value;
    // Listeners first: the UI has to follow the tap even if the save fails.
    notifyListeners();

    final save = onChanged;
    if (save == null) return;
    try {
      save(value);
    } catch (error) {
      debugPrint('flutter_dio_inspector: the language hook threw: $error');
    }
  }

  /// Flips between Chinese and English.
  void toggle() => language = _language.other;
}
