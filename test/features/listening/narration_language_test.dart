import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/features/book_reader/narration_language_controller.dart';

void main() {
  test('French only is available; ambiguous metadata needs consent, English has no fallback', () {
    expect(
      NarrationLanguageController.evaluate(['fr-FR']),
      NarrationLanguage.french,
    );
    expect(
      NarrationLanguageController.evaluate([]),
      NarrationLanguage.confirmationRequired,
    );
    expect(
      NarrationLanguageController.evaluate(['fr', 'en']),
      NarrationLanguage.confirmationRequired,
    );
    expect(
      NarrationLanguageController.evaluate(['und']),
      NarrationLanguage.confirmationRequired,
    );
    expect(
      NarrationLanguageController.evaluate(['en']),
      NarrationLanguage.unsupported,
    );
  });
}
