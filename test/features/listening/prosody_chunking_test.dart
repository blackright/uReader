import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/features/listening/prepared_text_map.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';

Future<int> words(String text) async =>
    text.trim().split(RegExp(r'\s+')).length;

void main() {
  test('a complete following sentence is not split just to fill the preceding chunk', () async {
    final first = '${'mot ' * 28}fin.';
    final second = '${'debut ' * 10}virgule, ${'suite ' * 20}fin.';
    final parts = await SpeechSegmenter(words)
        .streamPassage(
          textId: 't',
          version: 1,
          passageId: 'p',
          source: '$first $second',
        )
        .toList();
    expect(parts, hasLength(2));
    expect(parts.first.source.trim(), first);
    expect(parts.last.source.trim(), second);
  });

  test('short sentences share context when the complete prompt fits', () async {
    const source =
        'Une première phrase ! Une autre phrase ! Encore une phrase.';
    final parts = await SpeechSegmenter(words)
        .streamPassage(textId: 't', version: 1, passageId: 'p', source: source)
        .toList();
    expect(parts, hasLength(1));
    expect(parts.single.source, source);
    expect(parts.single.synthesis, source);
  });

  test(
    'an oversized sentence prefers its clause boundary to an orphan ending',
    () async {
      final source =
          '${'mot ' * 35}ensemble, ${'mot ' * 12}les uns des autres.';
      final parts = await SpeechSegmenter(words)
          .streamPassage(
            textId: 't',
            version: 1,
            passageId: 'p',
            source: source,
          )
          .toList();
      expect(parts.map((p) => p.source).join(), source);
      expect(parts.first.source.trimRight().endsWith(','), isTrue);
      expect(parts.last.synthesis.endsWith('les uns des autres.'), isTrue);
      for (final part in parts) {
        expect(await words(part.synthesis), lessThanOrEqualTo(50));
        expect(part.preparedMap!.prepared, part.synthesis);
      }
    },
  );

  test('model-compatible whitespace and terminal punctuation retain source offsets', () {
    const source = '«  Émilie\u00a0\u00a0lit\n\tici, »';
    final map = PreparedTextMap.fromSource(source);
    expect(map.prepared, 'Émilie lit ici.');
    expect(map.source, source);
    final start = map.prepared.indexOf('lit');
    final range = map.sourceRange(start, start + 3)!;
    expect(
      (range.start, range.end),
      (source.indexOf('lit'), source.indexOf('lit') + 3),
    );
  });

  test('demo and book preparation use the same chunking policy', () async {
    const source = 'Bonjour ! Nous partons ensemble, puis nous revenons.';
    final segmenter = SpeechSegmenter(words);
    final book = await segmenter
        .streamPassage(textId: 't', version: 1, passageId: 'p', source: source)
        .toList();
    final demo = await segmenter.segment(
      DemoText(
        id: 't',
        corpusVersion: 1,
        title: 'Test',
        passages: [Passage(id: 'p', textId: 't', ordinal: 0, text: source)],
      ),
    );
    expect(
      demo.map((p) => p.synthesis).toList(),
      book.map((p) => p.synthesis).toList(),
    );
    expect(demo.every((p) => p.preparedMap != null), isTrue);
  });
}
