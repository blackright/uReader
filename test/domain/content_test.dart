import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/app_error.dart';

void main() {
  final text = DemoText(
    id: 'demo',
    corpusVersion: 1,
    title: 'Exemple',
    passages: [Passage(id: 'p1', textId: 'demo', ordinal: 0, text: 'A😀é')],
  );
  test('Valide le contenu et refuse une coupure de surrogate UTF-16', () {
    expect(
      () => text.validate(
        Locator(
          textId: 'demo',
          corpusVersion: 1,
          passageId: 'p1',
          offsetUtf16: 3,
        ),
      ),
      returnsNormally,
    );
    for (final locator in [
      Locator(
        textId: 'other',
        corpusVersion: 1,
        passageId: 'p1',
        offsetUtf16: 0,
      ),
      Locator(
        textId: 'demo',
        corpusVersion: 2,
        passageId: 'p1',
        offsetUtf16: 0,
      ),
      Locator(
        textId: 'demo',
        corpusVersion: 1,
        passageId: 'unknown',
        offsetUtf16: 0,
      ),
      Locator(
        textId: 'demo',
        corpusVersion: 1,
        passageId: 'p1',
        offsetUtf16: 2,
      ),
      Locator(
        textId: 'demo',
        corpusVersion: 1,
        passageId: 'p1',
        offsetUtf16: 8,
      ),
    ]) {
      expect(() => text.validate(locator), throwsA(isA<AppError>()));
    }
  });
  test('Refuse passages croisés, doublons et ordre incohérent', () {
    for (final passages in [
      [Passage(id: 'p', textId: 'other', ordinal: 0, text: 'Texte')],
      [Passage(id: 'p', textId: 'demo', ordinal: 1, text: 'Texte')],
      [
        Passage(id: 'p', textId: 'demo', ordinal: 0, text: 'A'),
        Passage(id: 'p', textId: 'demo', ordinal: 1, text: 'B'),
      ],
    ]) {
      expect(
        () => DemoText(
          id: 'demo',
          corpusVersion: 1,
          title: 'T',
          passages: passages,
        ),
        throwsA(isA<AppError>()),
      );
    }
    expect(() => text.passages.clear(), throwsUnsupportedError);
  });
}
