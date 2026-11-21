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

    for (final end in ends) {
      var prepared = prepare(normalized.speech.substring(start, end));
      if (prepared.isEmpty) {
        last = end;
        continue;
      }
      final sourceRange = normalized.sourceRange(start, end);
      if (prepared.length > 4096 ||
          sourceRange.end - sourceRange.start > 4096 ||
          await countTokens(prepared) > 50) {
        if (last <= start ||
            prepare(normalized.speech.substring(start, last)).isEmpty) {
          throw const AppError(ErrorCode.storageLimitExceeded);
        }
        final completed = emit(last);
        if (completed != null) yield completed;
        prepared = prepare(normalized.speech.substring(start, end));
        if (prepared.isNotEmpty &&
            (prepared.length > 4096 || await countTokens(prepared) > 50)) {
          throw const AppError(ErrorCode.storageLimitExceeded);
        }
      }
      last = end;
      if (RegExp(r'[.!?;:]$')
          .hasMatch(normalized.speech.substring(start, end).trim())) {
        final completed = emit(end);
        if (completed != null) yield completed;
      }
    }
    if (last > start) {
      final completed = emit(last);
      if (completed != null) yield completed;
    }
    if (pending != null) yield pending!;
  }

  static String prepare(String value) => PreparedTextMap.prepare(value);

  Future<List<SpeechSegment>> segment(DemoText text) async {
    final result = <SpeechSegment>[];
    for (final passage in text.passages) {
      final normalized = const FrenchTextNormalizer().normalize(passage.text);
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
      var start = 0;
      var last = 0;
      void emit(int end) {
        final prepared = prepare(normalized.speech.substring(start, end));
        final range = normalized.sourceRange(start, end);
        if (prepared.isEmpty) {
          if (result.isEmpty ||
              result.last.end.passageId != passage.id ||
              result.last.end.offsetUtf16 != range.start) {
            throw const AppError(ErrorCode.invalidContent);
          }
          final previous = result.removeLast();
          result.add(
            SpeechSegment(
              passage.text.substring(previous.start.offsetUtf16, range.end),
              previous.synthesis,
              previous.start,
              Locator(
                textId: text.id,
                corpusVersion: text.corpusVersion,
                passageId: passage.id,
                offsetUtf16: range.end,
              ),
            ),
          );
          start = end;
          return;
        }
        Locator locator(int offset) => Locator(
          textId: text.id,
          corpusVersion: text.corpusVersion,
          passageId: passage.id,
          offsetUtf16: offset,
        );
        result.add(
          SpeechSegment(
            passage.text.substring(range.start, range.end),
            prepared,
            locator(range.start),
            locator(range.end),
          ),
        );
        start = end;
      }

      for (final end in ends) {
        var prepared = prepare(normalized.speech.substring(start, end));
        if (prepared.isEmpty) {
          last = end;
          continue;
        }
        if (prepared.length > 4096 || await countTokens(prepared) > 50) {
          if (last <= start ||
              prepare(normalized.speech.substring(start, last)).isEmpty) {
            throw const AppError(ErrorCode.storageLimitExceeded);
          }
          emit(last);
          prepared = prepare(normalized.speech.substring(start, end));
          if (prepared.isNotEmpty &&
              (prepared.length > 4096 || await countTokens(prepared) > 50)) {
            throw const AppError(ErrorCode.storageLimitExceeded);
          }
        }
        last = end;
        // Prefer sentence ends and never split a normalized expression.
        if (RegExp(r'[.!?;:]$')
            .hasMatch(normalized.speech.substring(start, end).trim())) {
          emit(end);
        }
      }
      if (last > start) emit(last);
    }
    if (result.isEmpty) throw const AppError(ErrorCode.invalidContent);
    return List.unmodifiable(result);
  }
}
