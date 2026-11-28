import 'books.dart';

enum ReaderMode { paged, scroll }

enum AudioPresentation { full, simple }

enum HighlightColor { yellow, green, blue, pink, purple }

class ExperiencePreferences {
  ExperiencePreferences({
    this.mode = ReaderMode.paged,
    this.lineHeight = 1.5,
    this.margins = 20,
    this.followEnabled = true,
    this.presentation = AudioPresentation.full,
    this.highlightColor = HighlightColor.yellow,
  }) {
    if (!lineHeight.isFinite ||
        !const [1.2, 1.5, 1.8].contains(lineHeight) ||
        !const [12.0, 20.0, 28.0].contains(margins)) {
      throw const BookFailure(BookError.invalidContent);
    }
  }
  final ReaderMode mode;
  final double lineHeight, margins;
  final bool followEnabled;
  final AudioPresentation presentation;
  final HighlightColor highlightColor;
}

/// Half-open range in canonical block order, including non-text resources.
class BookFlowPosition {
  BookFlowPosition({
    required this.key,
    required this.ordinal,
    required this.offsetUtf16,
  }) {
    if (ordinal < 0 || offsetUtf16 < 0) {
      throw const BookFailure(BookError.invalidLocator);
    }
  }
  final ContentKey key;
  final int ordinal, offsetUtf16;
}

class ParagraphRange {
  ParagraphRange({
    required this.id,
    required this.start,
    required this.end,
    required this.firstOrdinal,
    required this.lastOrdinal,
    required this.speechEligible,
  }) {
    if (id.isEmpty ||
        start.key != end.key ||
        start.chapterId != end.chapterId ||
        firstOrdinal < 0 ||
        lastOrdinal < firstOrdinal) {
      throw const BookFailure(BookError.invalidLocator);
    }
  }
  final String id;
  final BookLocator start, end;
  final int firstOrdinal, lastOrdinal;
  final bool speechEligible;
}

class ParagraphPage {
  ParagraphPage({
    required this.key,
    required this.generation,
    required List<ParagraphRange> paragraphs,
    this.nextOrdinal,
  }) : paragraphs = List.unmodifiable(paragraphs) {
    if (generation < 1 ||
        paragraphs.length > 50 ||
        paragraphs.any((p) => p.start.key != key) ||
        (nextOrdinal != null && nextOrdinal! < 0)) {
      throw const BookFailure(BookError.invalidCursor);
    }
  }
  final ContentKey key;
  final int generation;
  final List<ParagraphRange> paragraphs;
  final int? nextOrdinal;
}
