import 'prepared_text_map.dart';
import '../../domain/app_error.dart';
import '../../domain/content.dart';
import 'french_text_normalizer.dart';

class SpeechSegment {
  const SpeechSegment(
    this.source,
    this.synthesis,
    this.start,
    this.end, {
    this.preparedMap,
  });
  final PreparedTextMap? preparedMap;
  final String source, synthesis;
  final Locator start, end;
}

class SpeechSegmenter {
  const SpeechSegmenter(this.countTokens);
  final Future<int> Function(String) countTokens;

  /// Incremental production from a single bounded canonical passage.
  Stream<SpeechSegment> streamPassage({
    required String textId,
    required int version,
    required String passageId,
    required String source,
    int sourceOffset = 0,
  }) async* {
    if (sourceOffset < 0 || sourceOffset + source.length > 8192) {
      throw const AppError(ErrorCode.invalidContent);
    }
    final normalized = const FrenchTextNormalizer().normalize(
      source,
      maxSourceUnits: 8192,
    );
    final ends = <int>[];
    for (final span in normalized.spans) {
      if (span.replaced) {
        ends.add(span.speechEnd);
      } else {
        for (final match in RegExp(r'\s+|\S+').allMatches(
          normalized.speech.substring(span.speechStart, span.speechEnd),
        )) {
          ends.add(span.speechStart + match.end);
        }
      }
    }
    var start = 0, last = 0;
    var sentenceEnd = 0, clauseEnd = 0;
    SpeechSegment? pending;
    SpeechSegment? emit(int end) {
      final prepared = prepare(normalized.speech.substring(start, end));
      final range = normalized.sourceRange(start, end);
      Locator at(int offset) => Locator(
        textId: textId,
        corpusVersion: version,
        passageId: passageId,
        offsetUtf16: offset + sourceOffset,
      );
      if (prepared.isEmpty) {
        if (pending != null &&
            range.end + sourceOffset - pending!.start.offsetUtf16 > 4096) {
          throw const AppError(ErrorCode.storageLimitExceeded);
        }
        if (pending == null ||
            pending!.end.offsetUtf16 != range.start + sourceOffset) {
          throw const AppError(ErrorCode.invalidContent);
        }
        pending = SpeechSegment(
          source.substring(
            pending!.start.offsetUtf16 - sourceOffset,
            range.end,
          ),
          pending!.synthesis,
          pending!.start,
          at(range.end),
          preparedMap: pending!.preparedMap?.extendSource(
            source.substring(
              pending!.start.offsetUtf16 - sourceOffset,
              range.end,
            ),
          ),
        );
        start = end;
        return null;
      }
      final completed = pending;
      pending = SpeechSegment(
        source.substring(range.start, range.end),
        prepared,
        at(range.start),
        at(range.end),
        preparedMap: PreparedTextMap.fromNormalized(
          normalized,
          start,
          end,
          sourceOffset: sourceOffset,
        ),
      );
      start = end;
      return completed;
    }

    var base = 0;
    while (base < ends.length) {
      final checked = <int, bool>{};
      Future<bool> fits(int index) async {
        if (checked.containsKey(index)) return checked[index]!;
        final end = ends[index];
        final value = prepare(normalized.speech.substring(start, end));
        final range = normalized.sourceRange(start, end);
        final valid =
            value.isEmpty ||
            (value.length <= 4096 &&
                range.end - range.start <= 4096 &&
                await countTokens(value) <= 50);
        checked[index] = valid;
        return valid;
      }

      // Exponential search bounds token-count RPCs even in a very long block.
      var good = base - 1, bad = ends.length, step = 1;
      while (true) {
        final probe = (base + step - 1).clamp(base, ends.length - 1);
        if (await fits(probe)) {
          good = probe;
          if (probe == ends.length - 1) break;
          step *= 2;
        } else {
          bad = probe;
          break;
        }
      }
      var low = good + 1, high = bad - 1;
      while (low <= high) {
        final middle = (low + high) ~/ 2;
        if (await fits(middle)) {
          good = middle;
          low = middle + 1;
        } else {
          high = middle - 1;
        }
      }
      if (good < base) throw const AppError(ErrorCode.storageLimitExceeded);
      last = ends[good];
      sentenceEnd = 0;
      clauseEnd = 0;
      for (var i = base; i <= good; i++) {
        final tail = normalized.speech
            .substring(start, ends[i])
            .trimRight()
            .replaceAll(RegExp(r'[»”"\u0027’\]\)]+$'), '')
            .trimRight();
        if (RegExp(r'[.!?…]$').hasMatch(tail)) sentenceEnd = ends[i];
        if (RegExp(r'[,;:]$').hasMatch(tail)) clauseEnd = ends[i];
      }
      var boundary = last;
      if (good < ends.length - 1) {
        var useClause = sentenceEnd <= start;
        if (!useClause && clauseEnd > sentenceEnd) {
          final suffix = normalized.speech.substring(sentenceEnd);
          final terminal = RegExp(r'[.!?…](?:[»”"\u0027’\]\)])*(?=\s|$)')
              .firstMatch(suffix);
          final whole = prepare(
            suffix.substring(0, terminal?.end ?? suffix.length),
          );
          useClause = whole.length > 4096 || await countTokens(whole) > 50;
        }
        boundary = sentenceEnd > start && !useClause
            ? sentenceEnd
            : clauseEnd > start
            ? clauseEnd
            : last;
        final index = ends.indexOf(boundary, base);
        // Token counts need not be strictly monotone for every tokenizer. Always
        // revalidate a selected natural boundary, falling back to a checked one.
        if (!await fits(index) ||
            prepare(normalized.speech.substring(start, boundary)).isEmpty) {
          boundary = last;
        }
      }
      final completed = emit(boundary);
      if (completed != null) yield completed;
      while (base < ends.length && ends[base] <= start) {
        base++;
      }
      // Once the next prefix contains words, trailing punctuation can no longer
      // extend this segment. Publish now rather than preparing a second chunk.
      final lookaheadEnd = bad < ends.length
          ? ends[bad]
          : normalized.speech.length;
      if (pending != null &&
          start < lookaheadEnd &&
          prepare(normalized.speech.substring(start, lookaheadEnd))
              .isNotEmpty) {
        yield pending!;
        pending = null;
      }
    }
    if (pending != null) yield pending!;
  }

  static String prepare(String value) => PreparedTextMap.prepare(value);

  Future<List<SpeechSegment>> segment(DemoText text) async {
    final result = <SpeechSegment>[];
    for (final passage in text.passages) {
      // Retain the demo input bound while sharing the streaming book policy.
      if (passage.text.length > 4096) {
        throw ArgumentError('Text exceeds preparation limit');
      }
      result.addAll(
        await streamPassage(
          textId: text.id,
          version: text.corpusVersion,
          passageId: passage.id,
          source: passage.text,
        ).toList(),
      );
    }
    if (result.isEmpty) throw const AppError(ErrorCode.invalidContent);
    return List.unmodifiable(result);
  }
}
