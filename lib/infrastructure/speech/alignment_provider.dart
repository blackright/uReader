import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/ports.dart';
import '../../domain/word_alignment.dart';
import '../../features/listening/prepared_text_map.dart';
import '../../features/listening/french_text_normalizer.dart';
import 'attention_alignment_decoder.dart';

abstract interface class AlignmentProvider {
  WordAlignment? resolve({
    required Object? native,
    required SpeechRequest request,
    required Uint8List rawWav,
    required Uint8List publishedWav,
  });
}

/// Opt-in after a recorded G1 decision; legacy v1 audio needs no extension.
class AttentionAlignmentProvider implements AlignmentProvider {
  const AttentionAlignmentProvider({required this.enabled});
  final bool enabled;
  @override
  WordAlignment? resolve({
    required Object? native,
    required SpeechRequest request,
    required Uint8List rawWav,
    required Uint8List publishedWav,
  }) {
    if (!enabled || native == null) return null;
    try {
      if (native is! Map ||
          native['version'] != 1 ||
          native['audioSha256'] != sha256.convert(rawWav).toString() ||
          native['preparedSha256'] !=
              sha256.convert(utf8.encode(request.synthesisText)).toString() ||
          native['sampleRate'] != 24000 ||
          native['samples'] != (rawWav.length - 44) ~/ 2) {
        return null;
      }
      final rawRows = native['attention'], rawOffsets = native['tokenOffsets'];
      if (rawRows is! List ||
          rawRows.isEmpty ||
          rawRows.length > 250 ||
          rawOffsets is! List ||
          rawOffsets.isEmpty ||
          rawOffsets.length > 50) {
        return null;
      }
      final offsets = <(int, int)>[];
      for (final raw in rawOffsets) {
        if (raw is! List ||
            raw.length != 2 ||
            raw[0] is! int ||
            raw[1] is! int ||
            (raw[0] as int) < 0 ||
            (raw[1] as int) < (raw[0] as int) ||
            (raw[1] as int) > request.synthesisText.length) {
          return null;
        }
        offsets.add((raw[0] as int, raw[1] as int));
      }
      final rows = <List<double>>[];
      for (final row in rawRows) {
        if (row is! List ||
            row.length != offsets.length ||
            row.any((v) => v is! num)) {
          return null;
        }
        rows.add([for (final v in row) (v as num).toDouble()]);
      }
      final mapping = PreparedTextMap.fromSource(
        request.text,
        sourceOffset: request.start.offsetUtf16,
      );
      if (mapping.prepared != request.synthesisText) return null;
      final cues = <WordCue>[];
      for (final cue in decodePreparedAttention(
        attention: rows,
        tokenOffsets: offsets,
        prepared: request.synthesisText,
        sampleCount: (rawWav.length - 44) ~/ 2,
      )) {
        final span = mapping.sourceRange(cue.startUtf16, cue.endUtf16);
        if (span == null) continue;
        if (cues.isNotEmpty &&
            cues.last.source.start == span.start &&
            cues.last.source.end == span.end) {
          final previous = cues.removeLast();
          cues.add(WordCue(previous.startSample, cue.endSample, span));
        } else {
          cues.add(WordCue(cue.startSample, cue.endSample, span));
        }
      }
      final expected = mapping.wordSources
          .map((r) => '${r.start}:${r.end}')
          .toSet();
      final observed = cues
          .map((c) => '${c.source.start}:${c.source.end}')
          .toSet();
      // A missing source word cannot be advertised as a complete available alignment.
      if (cues.isEmpty ||
          expected.isEmpty ||
          expected.difference(observed).isNotEmpty) {
        return null;
      }
      return WordAlignment(
        audioSha256: sha256.convert(publishedWav).toString(),
        sourceSha256: sha256.convert(utf8.encode(request.text)).toString(),
        preparedSha256: sha256
            .convert(utf8.encode(request.synthesisText))
            .toString(),
        passageId: request.start.passageId,
        sourceStart: request.start.offsetUtf16,
        sourceEnd: request.end.offsetUtf16,
        samples: (publishedWav.length - 44) ~/ 2,
        alignerVersion: 'attention-l3h9-v1',
        normalizerVersion: FrenchTextNormalizer.version,
        preparerVersion: PreparedTextMap.version,
        cues: cues,
      );
    } on Exception {
      return null;
    } on ArgumentError {
      return null;
    } on TypeError {
      return null;
    }
  }
}
