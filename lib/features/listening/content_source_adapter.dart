import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../../domain/content.dart';
import 'speech_segmenter.dart';

/// Pull-based contract: callers retain only the current and anticipated segment.
abstract interface class SpeechSegmentCursor {
  Future<SpeechSegment?> next();
  Future<void> close();
}

/// Namespaced opaque identity within the unchanged native speech protocol v1.
class BookSpeechContext {
  BookSpeechContext(this.key, this.source)
    : wireId = 'book-${sha256.convert(utf8.encode(key.id))}';
  final ContentKey key;
  final BookNavigationSource source;
  final String wireId;
  Locator toWire(BookLocator locator) {
    if (locator.key != key) throw const BookFailure(BookError.invalidLocator);
    return Locator(
      textId: wireId,
      corpusVersion: key.version,
      passageId: locator.blockId,
      offsetUtf16: locator.offsetUtf16,
    );
  }

  Future<BookLocator> toBook(Locator locator) async {
    if (locator.textId != wireId || locator.corpusVersion != key.version) {
      throw const BookFailure(BookError.invalidLocator);
    }
    final block = await source.block(key, locator.passageId);
    final result = BookLocator(
      key: key,
      chapterId: block.chapterId,
      blockId: block.id,
      offsetUtf16: locator.offsetUtf16,
    );
    result.validate(block);
    return result;
  }
}

/// Corpus compatibility: it keeps its existing bounded, validated segmentation.
class DemoSegmentCursor implements SpeechSegmentCursor {
  DemoSegmentCursor(this.segments, {int start = 0}) : _index = start;
  final List<SpeechSegment> segments;
  int _index;
  bool _closed = false;
  @override
  Future<SpeechSegment?> next() async =>
      _closed || _index >= segments.length ? null : segments[_index++];
  @override
  Future<void> close() async {
    _closed = true;
  }
}
