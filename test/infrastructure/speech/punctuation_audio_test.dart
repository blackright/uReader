import 'package:flutter_test/flutter_test.dart';

import 'dart:typed_data';

import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/infrastructure/audio/punctuation_audio.dart';

import 'platform_speech_engine_test.dart' show wavFixture;

void main() {
  SpeechOutput output() => SpeechOutput(
    audioHandle: 'native',
    sampleRate: 24000,
    channels: 1,
    encoding: AudioEncoding.pcm16,
    durationMs: 1,
    byteSize: 92,
    start: Locator(
      textId: 't',
      corpusVersion: 1,
      passageId: 'p',
      offsetUtf16: 0,
    ),
    end: Locator(textId: 't', corpusVersion: 1, passageId: 'p', offsetUtf16: 1),
  );
  test('Pauses selon le signe source, y compris après guillemet', () {
    expect(PunctuationAudio.pauseMs('Bonjour ! » '), 350);
    expect(PunctuationAudio.pauseMs("'Bonjour !'"), 350);
    expect(PunctuationAudio.pauseMs('Réponse :'), 220);
    expect(PunctuationAudio.pauseMs('documents ;'), 220);
    expect(PunctuationAudio.pauseMs('pommes,'), 120);
    expect(PunctuationAudio.pauseMs('segment sans signe'), 0);
  });
  test('Ajout de silence sans modification des échantillons de parole', () {
    final bytes = wavFixture();
    bytes.setRange(
      44,
      bytes.length,
      List<int>.generate(48, (i) => i.isEven ? 0 : 16),
    );
    final result = PunctuationAudio.apply(bytes, output(), 'Bonjour.');
    expect(result.addedSamples, 8400);
    expect(result.bytes.sublist(44, bytes.length), bytes.sublist(44));
    expect(result.output.durationMs, 351);
    expect(result.output.byteSize, bytes.length + 8400 * 2);
    final again = PunctuationAudio.apply(
      result.bytes,
      result.output,
      'Bonjour.',
    );
    expect(again.addedSamples, 0);
  });
  test('Aucune pause ajoutée à une coupure sans ponctuation source', () {
    final bytes = wavFixture();
    final result = PunctuationAudio.apply(bytes, output(), 'fragment');
    expect(result.bytes, same(bytes));
    expect(result.addedSamples, 0);
  });
  test('La pause ne dépasse jamais le plafond PCM existant', () {
    final bytes = Uint8List(960044)..setRange(0, 44, wavFixture());
    final data = ByteData.sublistView(bytes);
    data.setUint32(4, bytes.length - 8, Endian.little);
    data.setUint32(40, bytes.length - 44, Endian.little);
    data.setInt16(bytes.length - 2, 4096, Endian.little);
    final original = output();
    final metadata = SpeechOutput(
      audioHandle: original.audioHandle,
      sampleRate: 24000,
      channels: 1,
      encoding: AudioEncoding.pcm16,
      durationMs: 20000,
      byteSize: bytes.length,
      start: original.start,
      end: original.end,
    );
    final result = PunctuationAudio.apply(bytes, metadata, 'Fin.');
    expect(result.bytes.length, 960044);
    expect(result.addedSamples, 0);
  });
}
