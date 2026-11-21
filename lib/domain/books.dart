import 'dart:typed_data';

import 'app_error.dart';
import 'content.dart' show ReadingMode;

enum BookError {
  invalidContent,
  invalidLocator,
  invalidCursor,
  limitExceeded,
  unsafeLink,
  invalidArchive,
  unsupportedContent,
  protectedContent,
  fixedLayoutUnsupported,
  unsupportedFormat,
  insufficientStorage,
  operationInProgress,
  unsafeContent,
  sourceUnavailable,
  cancelled,
  deadlineExceeded,
  revisionConflict,
  storageUnavailable,
}

class BookFailure implements Exception {
  const BookFailure(this.code);
  final BookError code;
  String get message => switch (code) {
    BookError.limitExceeded => 'Le livre dépasse les limites autorisées.',
    BookError.invalidLocator ||
    BookError.invalidCursor => 'Ce passage ne peut pas être retrouvé.',
    BookError.unsafeLink => 'Ce lien est refusé.',
    BookError.invalidArchive => 'Le fichier EPUB est invalide.',
    BookError.unsupportedContent => 'Ce contenu EPUB n’est pas pris en charge.',
    BookError.protectedContent =>
      'Le texte de ce livre est protégé et ne peut pas être importé.',
    BookError.fixedLayoutUnsupported =>
      'Les livres à mise en page fixe ne sont pas pris en charge.',
    BookError.unsupportedFormat =>
      'Sélectionnez un livre au format EPUB 2 ou EPUB 3.',
    BookError.insufficientStorage =>
      'Espace insuffisant. Libérez du stockage puis réessayez.',
    BookError.operationInProgress => 'Un import est déjà en cours.',
    BookError.unsafeContent => 'Ce livre contient une ressource non autorisée.',
    BookError.sourceUnavailable =>
      'Le fichier source est indisponible. Sélectionnez-le à nouveau.',
    BookError.cancelled => 'Import annulé.',
    BookError.deadlineExceeded =>
      'La préparation du livre a été interrompue. Réessayez.',
    BookError.revisionConflict => 'La position a été modifiée. Rechargez-la.',
    BookError.storageUnavailable => 'Le stockage est indisponible. Réessayez.',
    BookError.invalidContent => 'Le contenu du livre est invalide.',
  };
  @override
  String toString() => message;
}

void _id(String value) {
  try {
    requireIdentifier(value);
  } on AppError {
    throw const BookFailure(BookError.invalidContent);
  }
}

enum ContentKind { demo, book }

class ContentKey {
  ContentKey(this.kind, this.id, this.version) {
    _id(id);
    if (version < 1) throw const BookFailure(BookError.invalidContent);
  }
  final ContentKind kind;
  final String id;
  final int version;
  @override
  bool operator ==(Object other) =>
      other is ContentKey &&
      kind == other.kind &&
      id == other.id &&
      version == other.version;
  @override
  int get hashCode => Object.hash(kind, id, version);
}

class Book {
  Book({
    required this.key,
    required this.title,
    required List<String> authors,
    required List<String> languages,
    this.coverResource,
  }) : authors = List.unmodifiable(authors),
       languages = List.unmodifiable(languages) {
    if (key.kind != ContentKind.book || title.trim().isEmpty) {
      throw const BookFailure(BookError.invalidContent);
    }
  }
  final ContentKey key;
  final String title;
  final String? coverResource;
  final List<String> authors, languages;
}

class BookChapter {
  BookChapter({
    required this.key,
    required this.id,
    required this.ordinal,
    required this.title,
    required this.resource,
    required this.firstBlockOrdinal,
    required this.blockCount,
    required this.textUnits,
  }) {
    _id(id);
    if (ordinal < 0 ||
        firstBlockOrdinal < 0 ||
        blockCount < 0 ||
        textUnits < 0 ||
        title.trim().isEmpty) {
      throw const BookFailure(BookError.invalidContent);
    }
  }
  final ContentKey key;
  final String id, title, resource;
  final int ordinal, firstBlockOrdinal, blockCount, textUnits;
}

enum BookBlockKind {
  heading,
  paragraph,
  listItem,
  quote,
  tableCell,
  preformatted,
  image,
}

class BookLink {
  BookLink(this.target, this.startUtf16, this.endUtf16) {
    final uri = Uri.tryParse(target);
    if (uri == null ||
        target.isEmpty ||
        target.contains('\\') ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(target) ||
        startUtf16 < 0 ||
        endUtf16 <= startUtf16 ||
        uri.hasAuthority && !uri.hasScheme ||
        uri.hasScheme &&
            (uri.scheme != 'https' ||
                uri.host.isEmpty ||
                uri.userInfo.isNotEmpty)) {
      throw const BookFailure(BookError.unsafeLink);
    }
  }
  final String target;
  final int startUtf16, endUtf16;
}

class BookInline {
  BookInline({
    required this.startUtf16,
    required this.endUtf16,
    this.emphasis = false,
    this.strong = false,
    this.link,
  }) {
    if (startUtf16 < 0 || endUtf16 <= startUtf16) {
      throw const BookFailure(BookError.invalidContent);
    }
  }
  final int startUtf16, endUtf16;
  final bool emphasis, strong;
  final BookLink? link;
}

bool validUtf16Offset(String text, int offset) =>
    offset >= 0 &&
    offset <= text.length &&
    !(offset > 0 &&
        offset < text.length &&
        text.codeUnitAt(offset - 1) >= 0xd800 &&
        text.codeUnitAt(offset - 1) <= 0xdbff &&
        text.codeUnitAt(offset) >= 0xdc00 &&
        text.codeUnitAt(offset) <= 0xdfff);

class BookBlock {
  BookBlock({
    required this.key,
    required this.chapterId,
    required this.id,
    required this.ordinal,
    required this.kind,
    required this.text,
    this.speechEligible = true,
    this.resourceId,
    this.alternative,
    List<BookInline> inline = const [],
  }) : inline = List.unmodifiable(inline) {
    _id(chapterId);
    _id(id);
    if (ordinal < 0 || text.length > 8192 || inline.length > 128) {
      throw const BookFailure(BookError.limitExceeded);
    }
    // Reject malformed surrogate sequences, not only offsets splitting a pair.
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= text.length ||
            text.codeUnitAt(i) < 0xdc00 ||
            text.codeUnitAt(i) > 0xdfff) {
          throw const BookFailure(BookError.invalidContent);
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const BookFailure(BookError.invalidContent);
      }
    }
    for (final span in inline) {
      if (!validUtf16Offset(text, span.startUtf16) ||
          !validUtf16Offset(text, span.endUtf16) ||
          span.link != null &&
              (span.link!.startUtf16 != span.startUtf16 ||
                  span.link!.endUtf16 != span.endUtf16)) {
        throw const BookFailure(BookError.invalidContent);
      }
    }
  }
  final ContentKey key;
  final String chapterId, id, text;
  final int ordinal;
  final BookBlockKind kind;
  final bool speechEligible;
  final String? resourceId, alternative;
  final List<BookInline> inline;
}

class BookLocator {
  BookLocator({
    required this.key,
    required this.chapterId,
    required this.blockId,
    required this.offsetUtf16,
  }) {
    _id(chapterId);
    _id(blockId);
    if (offsetUtf16 < 0) throw const BookFailure(BookError.invalidLocator);
  }
  final ContentKey key;
  final String chapterId, blockId;
  final int offsetUtf16;
  void validate(BookBlock block) {
    if (key != block.key ||
        chapterId != block.chapterId ||
        blockId != block.id ||
        !validUtf16Offset(block.text, offsetUtf16)) {
      throw const BookFailure(BookError.invalidLocator);
    }
  }
}

class BookCursor {
  BookCursor({
    required this.key,
    required this.generation,
    required this.nextOrdinal,
  }) {
    if (generation < 1 || nextOrdinal < 0) {
      throw const BookFailure(BookError.invalidCursor);
    }
  }
  final ContentKey key;
  final int generation, nextOrdinal;
  void validate(ContentKey content, int currentGeneration) {
    if (content != key || currentGeneration != generation) {
      throw const BookFailure(BookError.invalidCursor);
    }
  }
}

class BookWindow {
  BookWindow({
    required this.key,
    required this.generation,
    required List<BookBlock> blocks,
    this.next,
  }) : blocks = List.unmodifiable(blocks) {
    if (generation < 1 ||
        blocks.length > 64 ||
        blocks.fold<int>(0, (sum, b) => sum + b.text.length) > 65536) {
      throw const BookFailure(BookError.limitExceeded);
    }
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].key != key ||
          i > 0 && blocks[i].ordinal != blocks[i - 1].ordinal + 1) {
        throw const BookFailure(BookError.invalidContent);
      }
    }
    next?.validate(key, generation);
    if (next != null &&
        (blocks.isEmpty || next!.nextOrdinal != blocks.last.ordinal + 1)) {
      throw const BookFailure(BookError.invalidCursor);
    }
  }
  final ContentKey key;
  final int generation;
  final List<BookBlock> blocks;
  final BookCursor? next;
  bool get done => next == null;
}

abstract interface class ContentLease {
  Future<void> release();
}

abstract interface class BookContentSource {
  Future<List<BookChapter>> chapters(ContentKey key);
  Future<BookWindow> window(
    ContentKey key,
    int generation, {
    BookCursor? after,
    int maxBlocks = 64,
    int maxUnits = 65536,
  });
  Future<BookLocator> resolveAnchor(
    ContentKey key,
    String resource,
    String fragment,
  );
  Future<void> validateLocator(BookLocator locator);
  Future<ContentLease> acquire(ContentKey key);
}

class BookPosition {
  BookPosition(this.locator, this.mode, this.revision) {
    if (revision < 1) throw const BookFailure(BookError.invalidLocator);
  }
  final BookLocator locator;
  final ReadingMode mode;
  final int revision;
}

abstract interface class BookPositionStore {
  Future<BookPosition?> read(ContentKey key, ReadingMode mode);
  Future<BookPosition> save(
    BookLocator locator,
    ReadingMode mode, {
    required int expectedRevision,
  });
}

class BookSourceChunk {
  BookSourceChunk({
    required Uint8List bytes,
    required this.eof,
    required this.totalBytes,
  }) : bytes = Uint8List.fromList(bytes) {
    if (bytes.length > 65536 ||
        totalBytes < bytes.length ||
        totalBytes > 100 * 1024 * 1024 ||
        bytes.isEmpty && !eof) {
      throw const BookFailure(BookError.limitExceeded);
    }
  }
  final Uint8List bytes;
  final bool eof;
  final int totalBytes;
}

abstract interface class BookDocumentSource {
  Future<String?> choose(String operationId, int generation);
  Future<BookSourceChunk> read(String handle, {int maxBytes = 65536});
  Future<void> close(String handle);
  Future<void> cancel(String operationId, int generation);
}

enum BookOperationKind { import, delete }

enum BookOperationPhase {
  copying,
  validating,
  validated,
  published,
  deleting,
  error,
}

class BookOperation {
  BookOperation({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.phase,
    required this.generation,
  }) {
    _id(id);
    _id(bookId);
    if (generation < 1) throw const BookFailure(BookError.invalidContent);
  }
  final String id, bookId;
  final BookOperationKind kind;
  final BookOperationPhase phase;
  final int generation;
}

abstract interface class BookOperationJournal {
  Future<List<BookOperation>> pending();
  Future<void> record(BookOperation operation);
  Future<void> forget(String operationId);
}
