import 'package:characters/characters.dart';

import '../../domain/paragraph_index.dart';
import '../../domain/word_alignment.dart';
import 'french_text_normalizer.dart';

class PreparedTextSpan {
  const PreparedTextSpan(this.preparedStart, this.preparedEnd, this.source);
  final int preparedStart, preparedEnd;
  final SourceSpan? source;
  bool get inserted => source == null;
}

class _Unit {
  const _Unit(this.text, this.range);
  final String text;
  final SourceSpan? range;
}

/// Composes source → normalized → exactly prepared. No word timing is invented.
class PreparedTextMap {
  PreparedTextMap._(
    this.source,
    this.sourceOffset,
    this.prepared,
    List<PreparedTextSpan> spans,
  ) : spans = List.unmodifiable(spans);
  static const version = 'prepared-map-v2';
  final String source, prepared;
  final int sourceOffset;
  final List<PreparedTextSpan> spans;
  factory PreparedTextMap.fromSource(String source, {int sourceOffset = 0}) {
    if (sourceOffset < 0 || sourceOffset + source.length > 8192) {
      throw ArgumentError('Invalid source bounds');
    }
    final normalized = const FrenchTextNormalizer().normalize(
      source,
      maxSourceUnits: 8192,
    );
    return PreparedTextMap.fromNormalized(
      normalized,
      0,
      normalized.speech.length,
      sourceOffset: sourceOffset,
    );
  }
  factory PreparedTextMap.fromNormalized(
    NormalizedFrenchText normalized,
    int start,
    int end, {
    int sourceOffset = 0,
  }) {
    final range = normalized.sourceRange(start, end);
    if (sourceOffset < 0 || sourceOffset + range.end > 8192) {
      throw ArgumentError('Invalid absolute source bounds');
    }
    final units = <_Unit>[];
    var offset = start;
    for (final cluster in normalized.speech.substring(start, end).characters) {
      final source = normalized.sourceRange(offset, offset + cluster.length);
      units.add(
        _Unit(
          cluster,
          SourceSpan(source.start + sourceOffset, source.end + sourceOffset),
        ),
      );
      offset += cluster.length;
    }
    return _build(
      normalized.source.substring(range.start, range.end),
      range.start + sourceOffset,
      units,
    );
  }

  /// Shared with SpeechSegmenter.prepare, so punctuation/case cannot drift.
  static String prepare(String value) => _build(value, 0, [
    for (final cluster in value.characters) _Unit(cluster, null),
  ]).prepared;

  static PreparedTextMap _build(String source, int offset, List<_Unit> input) {
    var units = <_Unit>[];
    for (final unit in [
      for (final original in input)
        for (final codeUnit in original.text.split(''))
          _Unit(codeUnit, original.range),
    ]) {
      if (RegExp('["“”„«»()\\[\\]]').hasMatch(unit.text)) continue;
      var text = unit.text
          .replaceAll('’', "'")
          .replaceAll('‘', "'")
          .replaceAll(':', ',')
          .replaceAll(';', ',');
      // Match the model's reference preparation without losing source ranges.
      if (RegExp(r'^\s$').hasMatch(text)) {
        text = ' ';
        if (units.isNotEmpty && units.last.text == ' ') {
          final previous = units.removeLast();
          units.add(
            _Unit(
              ' ',
              previous.range == null || unit.range == null
                  ? null
                  : SourceSpan(previous.range!.start, unit.range!.end),
            ),
          );
          continue;
        }
      }
      if (text == ',') {
        while (units.isNotEmpty && RegExp(r'^\s$').hasMatch(units.last.text)) {
          units.removeLast();
        }
      }
      units.add(_Unit(text, unit.range));
    }
    while (units.isNotEmpty && units.first.text.trim().isEmpty) {
      units.removeAt(0);
    }
    while (units.isNotEmpty && RegExp(r'^\s$').hasMatch(units.last.text)) {
      units.removeLast();
    }
    var text = units.map((u) => u.text).join();
    if (!RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text)) {
      return PreparedTextMap._(source, offset, '', const []);
    }
    final first = units.removeAt(0);
    // Preserve legacy preparation (first UTF-16 code unit capitalized).
    units.insert(
      0,
      _Unit(
        first.text.substring(0, 1).toUpperCase() + first.text.substring(1),
        first.range,
      ),
    );
    text = units.map((u) => u.text).join();
    if (RegExp(r'[,\-–—]$').hasMatch(text)) {
      final terminal = units.removeLast();
      units.add(_Unit('.', terminal.range));
    } else if (!RegExp(r'[.!?…]$').hasMatch(text)) {
      units.add(const _Unit('.', null));
    }
    final spans = <PreparedTextSpan>[];
    var at = 0;
    for (final unit in units) {
      spans.add(PreparedTextSpan(at, at + unit.text.length, unit.range));
      at += unit.text.length;
    }
    return PreparedTextMap._(
      source,
      offset,
      units.map((u) => u.text).join(),
      spans,
    );
  }

  PreparedTextMap extendSource(String value) {
    if (!value.startsWith(source) || sourceOffset + value.length > 8192) {
      throw ArgumentError('Invalid extension');
    }
    return PreparedTextMap._(value, sourceOffset, prepared, spans);
  }

  /// Expected source identities of pronounceable prepared words, deduplicating expansions.
  List<SourceSpan> get wordSources {
    final ranges = <String, SourceSpan>{};
    final words = RegExp(
      r"[\p{L}\p{M}\p{N}]+(?:['’\-‐‑][\p{L}\p{M}\p{N}]+)*",
      unicode: true,
    );
    for (final word in words.allMatches(prepared)) {
      final span = sourceRange(word.start, word.end);
      if (span != null) ranges['${span.start}:${span.end}'] = span;
    }
    return ranges.values.toList(growable: false);
  }

  SourceSpan? sourceRange(int start, int end) {
    final index = ParagraphIndex();
    if (start >= end ||
        !index.validTextBoundary(prepared, start) ||
        !index.validTextBoundary(prepared, end)) {
      throw ArgumentError('Invalid prepared grapheme range');
    }
    final mapped = spans
        .where(
          (s) =>
              s.preparedEnd > start &&
              s.preparedStart < end &&
              s.source != null,
        )
        .toList();
    if (mapped.isEmpty) return null;
    return SourceSpan(mapped.first.source!.start, mapped.last.source!.end);
  }
}
