import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/infrastructure/speech/alignment_provider.dart';
import 'package:prototype/infrastructure/speech/speech_messages.dart';

void main() {
  const text = 'Bonjour monde.';
  final wav = Uint8List(44 + 7680 * 2);
  Locator at(int n) =>
      Locator(textId: 'book', corpusVersion: 1, passageId: 'p', offsetUtf16: n);
  final request = SpeechRequest(
    requestId: 'r',
    token: SessionToken('s', 1),
    start: at(0),
    end: at(text.length),
    text: text,
    synthesisText: text,
    voiceId: 'v',
    bundleId: 'b',
  );
  Map<String, Object> native() => {
    'version': 1,
    'sampleRate': 24000,
    'samples': 7680,
    'audioSha256': sha256.convert(wav).toString(),
    'preparedSha256': sha256.convert(utf8.encode(text)).toString(),
    'tokenOffsets': [
      [0, 7],
      [8, 13],
    ],
    'attention': [
      [.9, .1],
      [.9, .1],
      [.1, .9],
      [.1, .9],
    ],
  };
  const provider = AttentionAlignmentProvider(enabled: true);
  test('legacy capabilities need no alignment field; unknown version is unavailable', () {
    expect(SpeechMessage.supportsAlignment({'protocolVersion': 1}), isFalse);
    expect(
      SpeechMessage.supportsAlignment({
        'protocolVersion': 1,
        'alignment': {'version': 2, 'available': true},
      }),
      isFalse,
    );
    expect(
      SpeechMessage.supportsAlignment({
        'protocolVersion': 1,
        'alignment': {'version': 1, 'available': true},
      }),
      isTrue,
    );
  });
  test('unqualified provider never adopts valid-looking native metadata', () {
    expect(
      const AttentionAlignmentProvider(enabled: false).resolve(
        native: native(),
        request: request,
        rawWav: wav,
        publishedWav: wav,
      ),
      isNull,
    );
  });
  test('identity join uses published padded WAV, source offsets and exact prepared text', () {
    final padded = Uint8List(wav.length + 480)..setRange(0, wav.length, wav);
    final result = provider.resolve(
      native: native(),
      request: request,
      rawWav: wav,
      publishedWav: padded,
    )!;
    expect(result.audioSha256, sha256.convert(padded).toString());
    expect(result.cues.first.source.start, 0);
    expect(result.cues.last.source.end, 13);
    expect(result.samples, 7920);
    expect(result.cues.last.endSample, 7680);
  });
  test(
    'hash, prepared identity, shape and nonfinite attention fail closed',
    () {
      for (final payload in [
        {...native(), 'audioSha256': 'f' * 64},
        {...native(), 'preparedSha256': 'f' * 64},
        {
          ...native(),
          'tokenOffsets': [
            [0, 7],
            [0, 7],
          ],
        },
        {
          ...native(),
          'attention': [
            [double.nan, .1],
          ],
        },
        {
          ...native(),
          'tokenOffsets': [
            [0, 999],
          ],
        },
        {
          ...native(),
          'attention': List.filled(251, [.5, .5]),
        },
      ]) {
        expect(
          provider.resolve(
            native: payload,
            request: request,
            rawWav: wav,
            publishedWav: wav,
          ),
          isNull,
        );
      }
    },
  );
}
