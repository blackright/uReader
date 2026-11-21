import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../../domain/word_selection.dart';
import '../../domain/paragraph_index.dart';

class WordSelectionSource {
  static Future<WordSelection> resolve(
    ParagraphNavigationSource source,
    BookLocator point,
  ) async {
    await source.validateLocator(point);
    final block = await source.block(point.key, point.blockId);
    if (!block.speechEligible) {
      throw const BookFailure(BookError.invalidLocator);
    }
    final range = await source.paragraphAt(point), index = ParagraphIndex();
    var blocks = [block], offset = point.offsetUtf16;
    var selected = WordSelection.at(blocks, offset);
    if (selected == null) throw const BookFailure(BookError.invalidLocator);
    if (selected.start.offsetUtf16 == 0 && range.firstOrdinal < block.ordinal) {
      final previous = await source.block(
        point.key,
        '${index.identity(block)}-s${index.slice(block) - 1}',
      );
      blocks = [previous, block];
      offset += previous.text.length;
      selected = WordSelection.at(blocks, offset);
    }
    if (selected != null &&
        selected.end.blockId == block.id &&
        selected.end.offsetUtf16 == block.text.length &&
        range.lastOrdinal > block.ordinal) {
      if (blocks.length == 2) {
        return WordSelection.at(blocks, offset, boundaryKnown: false)!;
      }
      final next = await source.block(
        point.key,
        '${index.identity(block)}-s${index.slice(block) + 1}',
      );
      selected = WordSelection.at([block, next], offset);
    }
    if (selected == null) throw const BookFailure(BookError.invalidLocator);
    await source.validateReadingBoundary(selected.start);
    return selected;
  }
}
