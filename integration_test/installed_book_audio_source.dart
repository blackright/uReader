import 'dart:io';

import 'package:drift/native.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/database/book_content_repository.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';

/// Opt-in device fixture. The test entry never opens the live product database:
/// it copies its stopped-app SQLite/WAL into the isolated run directory first.
/// Book content is read through the real repository; no position store is used.
class InstalledBookAudioSource {
  InstalledBookAudioSource._(this.book, this.content, this.database);
  final Book book;
  final BookContentRepository content;
  final PrototypeDatabase database;

  Future<BookLocator> firstSpeechLocator() async {
    BookCursor? cursor;
    do {
      final window = await content.window(book.key, 1, after: cursor);
      for (final block in window.blocks) {
        if (block.speechEligible && block.text.trim().isNotEmpty) {
          return BookLocator(
            key: book.key,
            chapterId: block.chapterId,
            blockId: block.id,
            offsetUtf16: 0,
          );
        }
      }
      cursor = window.next;
    } while (cursor != null);
    throw StateError('No narratable passage in selected book');
  }

  /// Explicit test start near a narrative chapter boundary; never saves a repère.
  Future<BookLocator> chapterTailLocator() async {
    final chapters = await content.chapters(book.key);
    final chapter = chapters.firstWhere((value) => value.blockCount >= 10);
    for (
      var ordinal = chapter.firstBlockOrdinal + chapter.blockCount - 1;
      ordinal >= chapter.firstBlockOrdinal;
      ordinal--
    ) {
      final window = await content.window(
        book.key,
        1,
        after: BookCursor(key: book.key, generation: 1, nextOrdinal: ordinal),
        maxBlocks: 1,
      );
      final block = window.blocks.single;
      if (!block.speechEligible || block.text.trim().isEmpty) continue;
      var offset = 0;
      for (final boundary in RegExp(r'[.!?]\s+').allMatches(block.text)) {
        if (block.text.length - boundary.end >= 25) offset = boundary.end;
      }
      return BookLocator(
        key: book.key,
        chapterId: block.chapterId,
        blockId: block.id,
        offsetUtf16: offset,
      );
    }
    throw StateError('No narratable chapter tail');
  }

  static Future<InstalledBookAudioSource> open({
    required String support,
    required Directory run,
    required String query,
  }) async {
    if (query.trim().length < 3) {
      throw ArgumentError('Explicit book query required');
    }
    final product = Directory('$support/ureader-prototype');
    if (await product.resolveSymbolicLinks() != product.path) {
      throw StateError('Unexpected product directory alias');
    }
    final clone = File('${run.path}/book-catalogue.sqlite');
    if (await clone.exists()) {
      throw StateError('Fresh catalogue clone required');
    }
    for (final suffix in ['', '-wal']) {
      final source = File('${product.path}/prototype.sqlite$suffix');
      final type = await FileSystemEntity.type(source.path, followLinks: false);
      if (suffix.isNotEmpty && type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.file ||
          await source.length() > 67108864) {
        throw StateError('Unsafe or oversized catalogue snapshot');
      }
      await source.copy('${clone.path}$suffix');
    }
    final db = PrototypeDatabase(NativeDatabase(clone));
    try {
      final books = await BookRepository(db)
          .readyPage(search: query, limit: 50);
      final selected = books
          .where(
            (book) => book.title.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
      if (selected.length != 1) {
        throw StateError('Book query must match exactly one ready book');
      }
      final content = BookContentRepository(
        db,
        await BookFileStore.open(product),
      );
      return InstalledBookAudioSource._(selected.single, content, db);
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  Future<void> close() => database.close();
}
