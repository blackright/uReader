import 'package:characters/characters.dart';

import 'books.dart';
import 'reader_experience.dart';

/// Structural IDs are assigned by the trusted projection, never by EPUB input.
class ParagraphIndex {
  static final _id = RegExp(r'^(c[0-9]+)-b([0-9]+)-s([0-9]+)$');
  String identity(BookBlock block) {
    final m = _id.firstMatch(block.id);
    if (m == null) {
      if (RegExp(r'^c[0-9]+-b[0-9]+-s').hasMatch(block.id)) {
        throw const BookFailure(BookError.invalidContent);
      }
      return block.id; // legacy non-sliced IDs remain individual paragraphs
    }
    if (m[1] != block.chapterId) {
      throw const BookFailure(BookError.invalidContent);
    }
    return '${m[1]}-b${m[2]}';
  }

  int slice(BookBlock block) {
    identity(block);
    return int.parse(_id.firstMatch(block.id)?[3] ?? '0');
  }

  bool validBoundary(BookBlock block, int offset) {
    return validTextBoundary(block.text, offset);
  }

  bool validTextBoundary(String text, int offset) {
    if (!validUtf16Offset(text, offset)) return false;
    var at = 0;
    if (offset == 0) return true;
    for (final cluster in Characters(text)) {
      at += cluster.length;
      if (at == offset) return true;
      if (at > offset) return false;
    }
    return false;
  }

  ParagraphRange range(BookBlock first, BookBlock last) {
    final id = identity(first);
    if (first.key != last.key ||
        first.chapterId != last.chapterId ||
        id != identity(last) ||
        slice(first) != 0 ||
        last.ordinal < first.ordinal ||
        last.ordinal - first.ordinal != slice(last) ||
        first.kind != last.kind ||
        first.speechEligible != last.speechEligible) {
      throw const BookFailure(BookError.invalidContent);
    }
    return ParagraphRange(
      id: id,
      start: BookLocator(
        key: first.key,
        chapterId: first.chapterId,
        blockId: first.id,
        offsetUtf16: 0,
      ),
      end: BookLocator(
        key: last.key,
        chapterId: last.chapterId,
        blockId: last.id,
        offsetUtf16: last.text.length,
      ),
      firstOrdinal: first.ordinal,
      lastOrdinal: last.ordinal,
      speechEligible: first.speechEligible,
    );
  }
}
