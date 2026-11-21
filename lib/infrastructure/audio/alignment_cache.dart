import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/word_alignment.dart';
import '../files/private_file_store.dart';

/// Derived metadata: never usable without the exact, leased WAV.
class AlignmentCache {
  AlignmentCache(this.files);
  final PrivateFileStore files;
  static Map<String, Object> encode(WordAlignment a) => {
    'version': 1,
    'audioSha256': a.audioSha256,
    'sourceSha256': a.sourceSha256,
    'preparedSha256': a.preparedSha256,
    'passageId': a.passageId,
    'sourceStart': a.sourceStart,
    'sourceEnd': a.sourceEnd,
    'samples': a.samples,
    'alignerVersion': a.alignerVersion,
    'normalizerVersion': a.normalizerVersion,
    'preparerVersion': a.preparerVersion,
    'cues': [
      for (final c in a.cues)
        [c.startSample, c.endSample, c.source.start, c.source.end],
    ],
  };
  static WordAlignment decode(Object? raw) {
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['cues'] is! List ||
        (raw['cues'] as List).length > 4096) {
      throw const FormatException('Alignment format');
    }
    return WordAlignment(
      audioSha256: raw['audioSha256'] as String,
      sourceSha256: raw['sourceSha256'] as String,
      preparedSha256: raw['preparedSha256'] as String,
      passageId: raw['passageId'] as String,
      sourceStart: raw['sourceStart'] as int,
      sourceEnd: raw['sourceEnd'] as int,
      samples: raw['samples'] as int,
      alignerVersion: raw['alignerVersion'] as String,
      normalizerVersion: raw['normalizerVersion'] as String,
      preparerVersion: raw['preparerVersion'] as String,
      cues: [for (final c in raw['cues'] as List) _cue(c)],
    );
  }

  static WordCue _cue(Object? raw) {
    if (raw is! List || raw.length != 4 || raw.any((v) => v is! int)) {
      throw const FormatException('Cue format');
    }
    return WordCue(
      raw[0] as int,
      raw[1] as int,
      SourceSpan(raw[2] as int, raw[3] as int),
    );
  }

  Future<void> publish(String key, WordAlignment alignment) =>
      files.writeAlignmentCache(
        key,
        utf8.encode(jsonEncode(encode(alignment))),
        alignment.audioSha256,
      );

  Future<WordAlignment?> read(String key) async {
    ResourceLease? lease;
    try {
      lease = await files.acquire('cache/audio/$key.wav');
      final bytes = await files.readAlignmentCache(key);
      if (bytes == null) return null;
      final value = decode(jsonDecode(utf8.decode(bytes)));
      final wav = await files.audioCacheFile(key);
      if (await wav.length() != 44 + value.samples * 2 ||
          (await sha256.bind(wav.openRead()).first).toString() !=
              value.audioSha256) {
        return null;
      }
      return value;
    } on Exception {
      return null;
    } on ArgumentError {
      return null;
    } on TypeError {
      return null;
    } finally {
      lease?.release();
    }
  }
}
