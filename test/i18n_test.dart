import 'package:flutter_dio_inspector/flutter_dio_inspector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PanelLanguage', () {
    test('round-trips through its name', () {
      for (final language in PanelLanguage.values) {
        expect(PanelLanguage.fromCode(language.name), language);
      }
    });

    test('falls back for an unknown, empty or missing code', () {
      // The code comes from the host app's settings, so it can be anything: a
      // language a newer version added, a truncated write, a key that was never
      // there. None of it should stop the panel from opening.
      expect(PanelLanguage.fromCode('ja'), PanelLanguage.en);
      expect(PanelLanguage.fromCode(''), PanelLanguage.en);
      expect(PanelLanguage.fromCode(null), PanelLanguage.en);
      expect(
        PanelLanguage.fromCode('ja', fallback: PanelLanguage.zh),
        PanelLanguage.zh,
      );
    });
  });

  group('PanelLanguageController', () {
    test('starts in English and toggles between the two', () {
      final controller = PanelLanguageController();
      addTearDown(controller.dispose);

      expect(controller.language, PanelLanguage.en);
      controller.toggle();
      expect(controller.language, PanelLanguage.zh);
      controller.toggle();
      expect(controller.language, PanelLanguage.en);
    });

    test('starts in the language it was given', () {
      final controller =
          PanelLanguageController(initial: PanelLanguage.zh);
      addTearDown(controller.dispose);

      expect(controller.language, PanelLanguage.zh);
    });

    test('reports every change to the persistence hook', () {
      final saved = <String>[];
      final controller = PanelLanguageController(
        onChanged: (PanelLanguage language) => saved.add(language.name),
      );
      addTearDown(controller.dispose);

      controller.toggle();
      // Setting the language it already has is not a change, so it must not be
      // written again — a restore that lands on the same value would otherwise
      // re-save on every launch.
      controller.language = PanelLanguage.zh;
      controller.toggle();

      expect(saved, <String>['zh', 'en']);
    });

    test('notifies listeners even when the hook throws', () {
      var calls = 0;
      final controller = PanelLanguageController(
        onChanged: (PanelLanguage _) {
          calls++;
          throw StateError('disk full');
        },
      );
      addTearDown(controller.dispose);

      var notified = 0;
      controller.addListener(() => notified++);

      controller.toggle();

      expect(calls, 1);
      // A failed settings write must not leave the panel stuck in the old
      // language.
      expect(controller.language, PanelLanguage.zh);
      expect(notified, 1);
    });
  });
}
