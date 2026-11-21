import 'dart:math';
import 'dart:typed_data';

import '../../domain/ports.dart';
import '../files/audio_cache.dart';

class PunctuatedAudio {
  const PunctuatedAudio(this.bytes, this.output, this.addedSamples);
  final Uint8List bytes;
  final SpeechOutput output;
  final int addedSamples;
}

/// Experimental minimum terminal quiet, without deleting or rewriting speech PCM.
class PunctuationAudio {
  static const version = 'punctuation-tail-v1';

  static int pauseMs(String source) {
    final end = source.replaceAll(RegExp(r'[\s»”"\u0027’\]\)]+$'), '');
    if (RegExp(r'[.!?]$').hasMatch(end)) return 350;
    if (RegExp(r'[;:]$').hasMatch(end)) return 220;
    if (end.endsWith(',')) return 120;
    return 0;
  }

  static PunctuatedAudio apply(
    Uint8List bytes,
    SpeechOutput output,
    String source,
  ) {
    AudioCache.validate(bytes, output);
    final samples = (bytes.length - 44) ~/ 2;
    final desired = pauseMs(source) * output.sampleRate ~/ 1000;
    final original = ByteData.sublistView(bytes);
    var quiet = 0;
    for (var i = samples - 1; i >= 0 && quiet < desired; i--) {
      if (original.getInt16(44 + i * 2, Endian.little).abs() > 128) break;
      quiet++;
    }
    final added = min(max(0, desired - quiet), 480000 - samples);
    if (added == 0) return PunctuatedAudio(bytes, output, 0);
    final padded = Uint8List(bytes.length + added * 2)
      ..setRange(0, bytes.length, bytes);
    final data = ByteData.sublistView(padded);
    data.setUint32(4, padded.length - 8, Endian.little);
    data.setUint32(40, padded.length - 44, Endian.little);
    final metadata = SpeechOutput(
      audioHandle: output.audioHandle,
      sampleRate: output.sampleRate,
      channels: output.channels,
      encoding: output.encoding,
      durationMs: (samples + added) * 1000 ~/ output.sampleRate,
      byteSize: padded.length,
      start: output.start,
      end: output.end,
    );
    AudioCache.validate(padded, metadata);
    return PunctuatedAudio(padded, metadata, added);
  }
}
