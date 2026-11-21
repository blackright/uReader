import 'package:drift/drift.dart';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../../domain/content.dart';
import 'prototype_database.dart';

/// Visual writes only in phase 4. Historical and book audio positions are untouched.
class BookPositionRepository implements VisualBookPositionStore {
  BookPositionRepository(this.db, this.content);
  final PrototypeDatabase db;
  final BookContentSource content;
  Future<void> _tail = Future.value();
  @override
  Future<BookPosition?> read(ContentKey key, ReadingMode mode) async {
    if (key.kind != ContentKind.book) {
      throw const BookFailure(BookError.invalidLocator);
    }
    await _tail;
    try {
      final rows = await db
          .customSelect(
            'SELECT * FROM book_positions WHERE book_id=? AND mode=?',
            variables: [Variable(key.id), Variable(mode.name)],
          )
          .get();
      if (rows.isEmpty) return null;
      final r = rows.single;
      return BookPosition(
        BookLocator(
          key: ContentKey(
            ContentKind.book,
            key.id,
            r.read<int>('projection_version'),
          ),
          chapterId: r.read<String>('chapter_id'),
          blockId: r.read<String>('block_id'),
          offsetUtf16: r.read<int>('offset_utf16'),
        ),
        mode,
        r.read<int>('revision'),
      );
    } on BookFailure {
      rethrow;
    } catch (_) {
      throw const BookFailure(BookError.storageUnavailable);
    }
  }

  @override
  Future<BookPosition> save(
    BookLocator locator,
    ReadingMode mode, {
    required int expectedRevision,
  }) async {
    if (mode != ReadingMode.visual) {
      throw const BookFailure(BookError.invalidLocator);
    }
    return (await saveVisual(
      locator,
      expectedRevision: expectedRevision,
      isCurrent: () => true,
    ))!;
  }

  @override
  Future<BookPosition?> saveVisual(
    BookLocator locator, {
    required int expectedRevision,
    required bool Function() isCurrent,
  }) => _savePosition(
    locator,
    ReadingMode.visual,
    expectedRevision: expectedRevision,
    isCurrent: isCurrent,
  );

  Future<BookPosition?> saveAudio(
    BookLocator locator, {
    required int expectedRevision,
    required bool Function() isCurrent,
  }) => _savePosition(
    locator,
    ReadingMode.audio,
    expectedRevision: expectedRevision,
    isCurrent: isCurrent,
  );

  Future<BookPosition?> _savePosition(
    BookLocator locator,
    ReadingMode mode, {
    required int expectedRevision,
    required bool Function() isCurrent,
  }) {
    final task = _tail.then((_) async {
      try {
        if (!isCurrent()) return null;
        return await db.transaction<BookPosition?>(() async {
          await content.validateLocator(locator);
          final rows = await db
              .customSelect(
                'SELECT revision,updated_at FROM book_positions WHERE book_id=? AND mode=?',
                variables: [Variable(locator.key.id), Variable(mode.name)],
              )
              .get();
          final revision = rows.isEmpty ? 0 : rows.single.read<int>('revision');
          if (expectedRevision < 0 || expectedRevision != revision) {
            throw const BookFailure(BookError.revisionConflict);
          }
          if (!isCurrent()) return null;
          final now = DateTime.now().millisecondsSinceEpoch;
          final oldTime = rows.isEmpty
              ? 0
              : rows.single.read<int>('updated_at');
          await db.customStatement(
            'INSERT INTO book_positions VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(book_id,mode) DO UPDATE SET projection_version=excluded.projection_version,chapter_id=excluded.chapter_id,block_id=excluded.block_id,offset_utf16=excluded.offset_utf16,revision=excluded.revision,updated_at=excluded.updated_at',
            [
              locator.key.id,
              mode.name,
              locator.key.version,
              locator.chapterId,
              locator.blockId,
              locator.offsetUtf16,
              revision + 1,
              now > oldTime ? now : oldTime + 1,
            ],
          );
          return BookPosition(locator, mode, revision + 1);
        });
      } on BookFailure {
        rethrow;
      } catch (_) {
        throw const BookFailure(BookError.storageUnavailable);
      }
    });
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  @override
  Future<void> flush() => _tail;
}
