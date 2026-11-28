import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/features/demo_reader/corpus_repository.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';

void main() {
  final segmenter = SpeechSegmenter((text) async => text.runes.length);
  test(
    'Guillemet et espaces finaux rattachés au dernier segment source',
    () async {
      const source = 'Il dit : « Bonjour ! » ';
      final text = DemoText(
        id: 't',
        corpusVersion: 1,
        title: 'Citation',
        passages: [Passage(id: 'p', textId: 't', ordinal: 0, text: source)],
      );
      final segments = await segmenter.segment(text);
      expect(segments.map((s) => s.source).join(), source);
      expect(segments.last.end.offsetUtf16, source.length);
      expect(segments.last.synthesis.endsWith('!'), isTrue);
    },
  );
  test('Couverture contiguë de tous les passages des dix textes', () async {
    final entries = await CorpusRepository(
      read: () => File('assets/corpus/fr_demo.json').readAsString(),
    ).load();
    for (final entry in entries) {
      final segments = await segmenter.segment(entry.text);
      for (final passage in entry.text.passages) {
        final parts = segments
            .where((s) => s.start.passageId == passage.id)
            .toList();
        expect(
          parts.map((s) => s.source).join(),
          passage.text,
          reason: passage.id,
        );
        var offset = 0;
        for (final part in parts) {
          expect(part.start.offsetUtf16, offset);
          offset = part.end.offsetUtf16;
        }
        expect(offset, passage.text.length);
      }
    }
  });
  test('Abréviations non coupées et aucun segment de ponctuation isolée', () async {
    const source =
        'Mme Martin rejoint M. Bernard. Le Dr Petit arrive à 14 h. Un dossier, etc. ?';
    final text = DemoText(
      id: 't',
      corpusVersion: 1,
      title: 'Essai',
      passages: [Passage(id: 'p', textId: 't', ordinal: 0, text: source)],
    );
    final parts = await SpeechSegmenter((_) async => 10).segment(text);
    expect(parts.map((s) => s.source).join(), source);
    expect(parts.any((s) => s.synthesis.contains('monsieur Bernard')), isTrue);
    expect(parts.any((s) => s.synthesis.contains('quatorze heures')), isTrue);
    expect(
      parts.every(
        (s) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(s.synthesis),
      ),
      isTrue,
    );
  });
  test('Les courtes propositions gardent leur contexte et leur ponctuation interne', () async {
    const source =
        'Réponse : oui, les documents utiles ; le reste peut attendre.';
    final text = DemoText(
      id: 't',
      corpusVersion: 1,
      title: 'Essai',
      passages: [Passage(id: 'p', textId: 't', ordinal: 0, text: source)],
    );
    final parts = await SpeechSegmenter((_) async => 10).segment(text);
    expect(parts.length, 1);
    expect(parts.single.source, source);
    expect(
      parts.single.synthesis,
      'Réponse, oui, les documents utiles, le reste peut attendre.',
    );
    expect(parts.map((s) => s.source).join(), source);
  });
}
