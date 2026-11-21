import 'dart:math' as math;

class LaboratoryCue {
  const LaboratoryCue(
    this.startSample,
    this.endSample,
    this.startUtf16,
    this.endUtf16,
  );
  final int startSample, endSample, startUtf16, endUtf16;
}

/// Experimental monotone Viterbi alignment over actual attention, not uniform timing.
/// Never imported by product code. Must be qualified audiovisually before adoption.
List<LaboratoryCue> decodeAttention({
  required List<List<double>> attention,
  required List<(int, int)> tokenOffsets,
  required String prepared,
  required int sampleCount,
  int sampleRate = 24000,
  double frameRate = 12.5,
}) {
  final frames = (sampleCount * frameRate / sampleRate).ceil(),
      tokens = tokenOffsets.length;
  if (sampleCount <= 0 ||
      sampleCount > 480000 ||
      tokens < 1 ||
      tokens > 50 ||
      frames < tokens ||
      frames > 250 ||
      attention.length < frames ||
      attention.length > 250) {
    throw ArgumentError('Unsupported laboratory alignment shape');
  }
  for (final row in attention) {
    if (row.length != tokens ||
        row.any((p) => !p.isFinite || p < 0 || p > 1) ||
        row.fold<double>(0, (a, b) => a + b) <= 0) {
      throw ArgumentError('Invalid attention');
    }
  }
  final cost = List.generate(
    frames,
    (_) => List.filled(tokens, double.infinity),
  );
  final moved = List.generate(frames, (_) => List.filled(tokens, false));
  cost[0][0] = -math.log(math.max(attention[0][0], 1e-12));
  for (var f = 1; f < frames; f++) {
    for (var t = 0; t < tokens; t++) {
      final stay = cost[f - 1][t],
          advance = t == 0 ? double.infinity : cost[f - 1][t - 1];
      moved[f][t] = advance < stay;
      cost[f][t] =
          math.min(stay, advance) - math.log(math.max(attention[f][t], 1e-12));
    }
  }
  final path = List.filled(frames, 0);
  var t = tokens - 1;
  for (var f = frames - 1; f >= 0; f--) {
    path[f] = t;
    if (f > 0 && moved[f][t]) t--;
  }
  final cues = <LaboratoryCue>[];
  final words = RegExp(
    r"[\p{L}\p{M}\p{N}]+(?:['’\-‐‑][\p{L}\p{M}\p{N}]+)*",
    unicode: true,
  );
  for (final word in words.allMatches(prepared)) {
    final relevant = <int>{
      for (var i = 0; i < tokens; i++)
        if (tokenOffsets[i].$1 < word.end && tokenOffsets[i].$2 > word.start) i,
    };
    final positions = [
      for (var f = 0; f < frames; f++)
        if (relevant.contains(path[f])) f,
    ];
    if (positions.isEmpty) {
      continue; // An absent word stays absent, never gets a fabricated time.
    }
    cues.add(
      LaboratoryCue(
        (positions.first * sampleRate / frameRate).round(),
        math.min(
          sampleCount,
          ((positions.last + 1) * sampleRate / frameRate).round(),
        ),
        word.start,
        word.end,
      ),
    );
  }
  return cues;
}
