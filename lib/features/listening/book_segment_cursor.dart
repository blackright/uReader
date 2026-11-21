import 'dart:async';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../../domain/reader_experience.dart';
import 'content_source_adapter.dart';
import 'speech_segmenter.dart';

/// One canonical block in memory, incremental segmentation and no book DemoText.
class BookSegmentCursor implements SpeechSegmentCursor {
  BookSegmentCursor(
    this.context,
    this.segmenter, {
    this.from,
    this.exactFrom = false,
    this.onlyChapter,
  });
  final BookSpeechContext context;
  final SpeechSegmenter segmenter;
  final BookLocator? from;
  final bool exactFrom;
  final String? onlyChapter;
  ContentLease? _lease;
  StreamIterator<SpeechSegment>? _segments;
  BookWindow? _window;
  int _ordinal = 0;
  bool _initialized = false, _closed = false, _busy = false, _done = false;
  Future<void>? _closing;
  int get retainedBlocks => _window?.blocks.length ?? 0;
  @override
  Future<SpeechSegment?> next() async {
    if (_closed || _done) return null;
    if (_busy) throw const BookFailure(BookError.operationInProgress);
    _busy = true;
    try {
      if (!_initialized) {
        _initialized = true;
        final lease = await context.source.acquire(context.key);
        if (_closed) {
          await lease.release();
          return null;
        }
        _lease = lease;
        if (from != null) {
          await context.source.validateLocator(from!);
          _ordinal = (await context.source.block(
            context.key,
            from!.blockId,
          )).ordinal;
        }
      }
      while (!_closed) {
        final iterator = _segments;
        if (iterator != null && await iterator.moveNext()) {
          if (_closed) return null;
          final segment = iterator.current;
          if (from != null &&
              segment.start.passageId == from!.blockId &&
              segment.end.offsetUtf16 <= from!.offsetUtf16) {
            continue;
          }
          return segment;
        }
        _segments = null;
        if (_window != null && _window!.next == null) {
          _done = true;
          return null;
        }
        final window = await context.source.window(
          context.key,
          1,
          after: BookCursor(
            key: context.key,
            generation: 1,
            nextOrdinal: _ordinal,
          ),
          maxBlocks: 1,
          maxUnits: 8192,
        );
        if (_closed) return null;
        _window = window;
        if (window.blocks.isEmpty) {
          _done = true;
          return null;
        }
        final block = window.blocks.single;
        if (onlyChapter != null && block.chapterId != onlyChapter) {
          _done = true;
          return null;
        }
        _ordinal = block.ordinal + 1;
        if (!block.speechEligible || block.text.trim().isEmpty) continue;
        _segments = StreamIterator(
          segmenter.streamPassage(
            textId: context.wireId,
            version: context.key.version,
            passageId: block.id,
            source: exactFrom && block.id == from?.blockId
                ? block.text.substring(from!.offsetUtf16)
                : block.text,
            sourceOffset: exactFrom && block.id == from?.blockId
                ? from!.offsetUtf16
                : 0,
          ),
        );
      }
      return null;
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= _close();
  }

  Future<void> _close() async {
    await _segments?.cancel();
    _segments = null;
    _window = null;
    await _lease?.release();
    _lease = null;
  }
}

/// Logical navigation stays independent of audio generation and presentation.
class BookParagraphCommands {
  static Future<ParagraphRange> resolve(
    BookSpeechContext context,
    BookLocator at,
  ) async {
    context.toWire(at);
    final source = context.source;
    if (source is! ParagraphNavigationSource) {
      throw const BookFailure(BookError.unsupportedContent);
    }
    await source.validateLocator(at);
    final range = await source.paragraphAt(at);
    context.toWire(range.start);
    if (!range.speechEligible) {
      throw const BookFailure(BookError.unsupportedContent);
    }
    await source.validateReadingBoundary(range.start);
    return range;
  }

  static Future<BookLocator?> neighbor(
    BookSpeechContext context,
    BookLocator at,
    bool forward,
    bool Function() cancelled,
  ) async {
    var range = await resolve(context, at);
    final source = context.source;
    final chapters = await source.chapters(context.key);
    final end = chapters.fold<int>(
      0,
      (n, c) => n > c.firstBlockOrdinal + c.blockCount
          ? n
          : c.firstBlockOrdinal + c.blockCount,
    );
    while (!cancelled()) {
      final ordinal = forward ? range.lastOrdinal + 1 : range.firstOrdinal - 1;
      if (ordinal < 0 || ordinal >= end) return null;
      final window = await source.window(
        context.key,
        1,
        after: BookCursor(
          key: context.key,
          generation: 1,
          nextOrdinal: ordinal,
        ),
        maxBlocks: 1,
        maxUnits: 8192,
      );
      if (cancelled()) return null;
      final block = window.blocks.single;
      range = await (source as ParagraphNavigationSource).paragraphAt(
        BookLocator(
          key: context.key,
          chapterId: block.chapterId,
          blockId: block.id,
          offsetUtf16: 0,
        ),
      );
      if (range.speechEligible) return range.start;
    }
    return null;
  }
}
