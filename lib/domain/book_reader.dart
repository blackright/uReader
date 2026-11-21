import 'dart:typed_data';

import 'books.dart';
import 'reader_experience.dart';

enum ReaderTheme { light, dark }

class ReaderPreferences {
  ReaderPreferences({this.fontScale = 1, this.theme = ReaderTheme.light}) {
    if (!fontScale.isFinite || fontScale < 0.75 || fontScale > 2) {
      throw const BookFailure(BookError.invalidContent);
    }
  }
  final double fontScale;
  final ReaderTheme theme;
}

abstract interface class ReaderPreferenceStore {
  Future<ReaderPreferences> read();
  Future<void> save(ReaderPreferences preferences);
}

abstract interface class ExperiencePreferenceStore {
  Future<ExperiencePreferences> read();
  Future<void> save(ExperiencePreferences value, {ReaderPreferences? reader});
  Future<void> flush();
}

class BookImagePayload {
  BookImagePayload(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width, height;
}

/// Additional capabilities; basic ContentSource adapters remain valid.
abstract interface class BookNavigationSource implements BookContentSource {
  Future<BookBlock> block(ContentKey key, String blockId);
  Future<BookWindow> windowAt(BookLocator locator, int generation);
  Future<BookWindow> windowBefore(
    ContentKey key,
    int generation,
    int firstOrdinal,
  );
  Future<(int, int)> progress(BookLocator locator);
  Future<BookImagePayload?> image(
    ContentKey key,
    String resourceId, {
    bool Function()? cancelled,
  });
}

abstract interface class VisualBookPositionStore implements BookPositionStore {
  Future<BookPosition?> saveVisual(
    BookLocator locator, {
    required int expectedRevision,
    required bool Function() isCurrent,
  });
  Future<void> flush();
}

extension IdentifiedBookNote on BookBlock {
  bool get isIdentifiedNote => !speechEligible && kind != BookBlockKind.image;
}

/// Optional reader foundation capability, preserving existing source adapters.
abstract interface class ParagraphNavigationSource
    implements BookNavigationSource {
  Future<ParagraphRange> paragraphAt(BookLocator locator);
  Future<ParagraphPage> paragraphs(
    ContentKey key,
    int generation, {
    BookCursor? after,
    int limit = 50,
  });
  Future<void> validateReadingBoundary(BookLocator locator);
}
