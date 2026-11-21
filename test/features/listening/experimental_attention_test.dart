import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/alignment/attention_decoder.dart';

void main() {
  test(
    'attention, not character count, selects a non-uniform word boundary',
    () {
      final cues = decodeAttention(
        attention: [
          [.99, .01],
          [.99, .01],
          [.99, .01],
          [.01, .99],
        ],
        tokenOffsets: [(0, 7), (8, 10)],
        prepared: 'Bonjour là',
        sampleCount: 7680,
      );
      expect(cues[0].endSample, 5760);
      expect(cues[1].startSample, 5760);
    },
  );
  test('termination row is excluded; invalid/partial attention cannot invent words', () {
    final cues = decodeAttention(
      attention: [
        [.99, .01],
        [.99, .01],
        [.99, .01],
        [.01, .99],
        [0, 1],
      ],
      tokenOffsets: [(0, 7), (8, 10)],
      prepared: 'Bonjour là',
      sampleCount: 7680,
    );
    expect(cues.last.endSample, 7680);
    expect(
      () => decodeAttention(
        attention: [
          [double.nan],
        ],
        tokenOffsets: [(0, 7)],
        prepared: 'Bonjour',
        sampleCount: 1920,
      ),
      throwsArgumentError,
    );
    expect(
      () => decodeAttention(
        attention: [
          [1],
        ],
        tokenOffsets: [(0, 7)],
        prepared: 'Bonjour',
        sampleCount: 3840,
      ),
      throwsArgumentError,
    );
  });
}
