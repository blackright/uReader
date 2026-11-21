import 'books.dart';
import 'paragraph_index.dart';

/// Canonical source selection, never a timing or a synthesized-word estimate.
class WordSelection {
  WordSelection._(this.start, this.end, this.text, {this.boundaryKnown = true});
  final BookLocator start, end;
  final String text;
  final bool boundaryKnown;
  bool get canStart =>
      boundaryKnown && start.blockId == end.blockId && text.length <= 4096;
  static final words = RegExp(
    r"[\p{L}\p{M}\p{N}]+(?:['’\-‐‑][\p{L}\p{M}\p{N}]+|[.,][\p{N}]+)*",
    unicode: true,
  );
  static WordSelection? at(
    List<BookBlock> blocks,
    int offset, {
    bool boundaryKnown = true,
  }) {
    if (blocks.isEmpty || blocks.length > 2) return null;
    final text = blocks.map((b) => b.text).join();
    RegExpMatch? found;
    for (final m in words.allMatches(text)) {
      if (offset >= m.start && offset < m.end) {
        found = m;
        break;
      }
      if (offset == m.end) found = m;
    }
    if (found == null ||
        !ParagraphIndex().validTextBoundary(text, found.start) ||
        !ParagraphIndex().validTextBoundary(text, found.end)) {
      return null;
    }
    BookLocator point(int n, {bool end = false}) {
      var base = 0;
      for (final b in blocks) {
        if (n < base + b.text.length ||
            end && n == base + b.text.length ||
            b == blocks.last) {
          return BookLocator(
            key: b.key,
            chapterId: b.chapterId,
            blockId: b.id,
            offsetUtf16: n - base,
          );
        }
        base += b.text.length;
      }
      throw const BookFailure(BookError.invalidLocator);
    }

    return WordSelection._(
      point(found.start),
      point(found.end, end: true),
      found.group(0)!,
      boundaryKnown: boundaryKnown,
    );
  }
}
