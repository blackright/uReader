import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/features/listening/prepared_text_map.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';

void main() {
  test('preparation remains exactly compatible with the prior algorithm', () {
    String legacy(String value) {
      var text = value
          .replaceAll(RegExp('["“”„«»()\\[\\]]'), '')
          .replaceAll('’', "'")
          .replaceAll('‘', "'")
          .replaceAll(':', ',')
          .replaceAll(';', ',')
          .replaceAll(RegExp(r'\s+,'), ',')
          .trim();
      if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text)) return '';
      text = text.substring(0, 1).toUpperCase() + text.substring(1);
      if (!RegExp(r'[.!?,]$').hasMatch(text)) text += '.';
      return text;
    }

    const atoms = [
      '(',
      ')',
      '«',
      '»',
      'e\u0301',
      '😀',
      'ß',
      ' ',
      '\n',
      '\u00a0',
      ':',
      ';',
      ',',
      '’',
    ];
    for (final a in atoms) {
      for (final b in atoms) {
        final text = '$a$b jardin';
        expect(SpeechSegmenter.prepare(text), legacy(text), reason: text);
      }
    }
  });
  test('expansion keeps full absolute source range through preparation', () {
    final map = PreparedTextMap.fromSource(
      '« 21 pommes à 9 h 30 »',
      sourceOffset: 17,
    );
    expect(map.prepared, 'Vingt-et-un pommes à neuf heures trente.');
    final n = map.prepared.indexOf('et-un');
    final range = map.sourceRange(n, n + 5)!;
    expect((range.start, range.end), (19, 21));
    final time = map.prepared.indexOf('heures');
    final hour = map.sourceRange(time, time + 6)!;
    expect((hour.start, hour.end), (31, 37));
    expect(map.spans.last.inserted, isTrue);
    expect(
      map.sourceRange(map.prepared.length - 1, map.prepared.length),
      isNull,
    );
  });
  test(
    'source is preserved; Unicode, whitespace, deletion and case compose',
    () {
      const source = '  (e\u0301cole) : l’amitié 😀  ';
      final map = PreparedTextMap.fromSource(source);
      expect(map.source, source);
      expect(map.prepared, "E\u0301cole, l'amitié 😀.");
      expect(map.sourceRange(0, 2)!.start, 3);
      expect(() => map.sourceRange(1, 2), throwsArgumentError);
      final emoji = map.prepared.indexOf('😀');
      expect(() => map.sourceRange(emoji + 1, emoji + 2), throwsArgumentError);
    },
  );
  test(
    'stream maps are exactly the synthesized text and retain block offsets',
    () async {
      final segments = await SpeechSegmenter((_) async => 1)
          .streamPassage(
            textId: 'book',
            version: 1,
            passageId: 'slice',
            source: '21 pommes. Puis 250 grammes.',
            sourceOffset: 200,
          )
          .toList();
      for (final segment in segments) {
        expect(segment.preparedMap!.prepared, segment.synthesis);
        expect(segment.preparedMap!.source, segment.source);
        expect(segment.preparedMap!.sourceOffset, segment.start.offsetUtf16);
      }
      expect(segments.first.preparedMap!.sourceRange(0, 5)!.start, 200);
      expect(segments.first.preparedMap!.sourceRange(0, 5)!.end, 202);
    },
  );
}
