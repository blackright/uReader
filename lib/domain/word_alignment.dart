import 'content.dart';

/// Source offsets remain UTF-16 coordinates, not estimated word times.
class SourceSpan {
  SourceSpan(this.start, this.end) {
    if (start < 0 || end <= start) throw ArgumentError('Invalid source span');
  }
  final int start, end;
}

bool validAudioSha(String value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

enum PlayerClockState { playing, paused, buffering, stopped }

class PlayerClockSample {
  const PlayerClockSample({
    required this.token,
    required this.segmentId,
    required this.audioSha256,
    required this.position,
    required this.state,
    required this.monotonicMicros,
  });
  final SessionToken token;
  final String segmentId, audioSha256;
  final Duration position;
  final PlayerClockState state;
  final int monotonicMicros;
}

/// Immutable source cues tied to the exact published WAV and transformation versions.
class WordCue {
  WordCue(this.startSample, this.endSample, this.source) {
    if (startSample < 0 || endSample <= startSample) {
      throw ArgumentError('Invalid cue time');
    }
  }
  final int startSample, endSample;
  final SourceSpan source;
}

class WordAlignment {
  WordAlignment({
    required this.audioSha256,
    required this.sourceSha256,
    required this.preparedSha256,
    required this.passageId,
    required this.sourceStart,
    required this.sourceEnd,
    required this.samples,
    required this.alignerVersion,
    required this.normalizerVersion,
    required this.preparerVersion,
    required List<WordCue> cues,
  }) : cues = List.unmodifiable(cues) {
    if (![audioSha256, sourceSha256, preparedSha256].every(validAudioSha) ||
        passageId.isEmpty ||
        sourceStart < 0 ||
        sourceEnd <= sourceStart ||
        sourceEnd > 8192 ||
        samples < 1 ||
        samples > 480000 ||
        [
          alignerVersion,
          normalizerVersion,
          preparerVersion,
        ].any((v) => !RegExp(r'^[a-zA-Z0-9_.-]{1,96}$').hasMatch(v)) ||
        cues.isEmpty ||
        cues.length > 4096) {
      throw ArgumentError('Invalid alignment identity or budget');
    }
    var last = 0;
    for (final cue in cues) {
      if (cue.startSample < last ||
          cue.endSample > samples ||
          cue.source.start < sourceStart ||
          cue.source.end > sourceEnd) {
        throw ArgumentError('Invalid alignment range');
      }
      last = cue.endSample;
    }
  }
  final String audioSha256, sourceSha256, preparedSha256, passageId;
  final String alignerVersion, normalizerVersion, preparerVersion;
  final int sourceStart, sourceEnd, samples;
  final List<WordCue> cues;

  WordCue? at(Duration position) {
    final sample = position.inMicroseconds * 24000 ~/ 1000000;
    var low = 0, high = cues.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (cues[mid].endSample <= sample) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low < cues.length && cues[low].startSample <= sample
        ? cues[low]
        : null;
  }
}
