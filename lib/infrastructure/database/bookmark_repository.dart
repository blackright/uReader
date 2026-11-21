import 'dart:math';

import 'package:drift/drift.dart';

import '../../domain/bookmarks.dart';
import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import 'prototype_database.dart';

/// v3 authoritative locators only. No page numbers, excerpts or private diagnostics.
class BookmarkRepository implements BookmarkStore {
  BookmarkRepository(
    this.db,
    this.source, {
    int Function()? now,
    String Function()? idFactory,
  }) : now = now ?? (() => DateTime.now().microsecondsSinceEpoch),
       idFactory = idFactory ?? _id;
  final PrototypeDatabase db;
  final ParagraphNavigationSource source;
  final int Function() now;
  final String Function() idFactory;
  Future<void> _tail = Future.value();
  static String _id() {
    final r = Random.secure();
    return List.generate(
      4,
      (_) => r.nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
    ).join();
  }

  static bool _validId(String value) =>
      RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$').hasMatch(value);
  Future<void> _ready(ContentKey key) async {
    if (key.kind != ContentKind.book) {
      throw const BookFailure(BookError.invalidLocator);
    }
    final rows = await db
        .customSelect(
          'SELECT state,projection_version FROM books WHERE book_id=?',
          variables: [Variable(key.id)],
        )
        .get();
    if (rows.length != 1 ||
        rows.single.read<String>('state') != 'ready' ||
        rows.single.read<int>('projection_version') != key.version) {
      throw const BookFailure(BookError.sourceUnavailable);
    }
  }

  Bookmark _row(QueryRow r) => Bookmark(
    id: r.read<String>('bookmark_id'),
    createdAt: r.read<int>('created_at'),
    locator: BookLocator(
      key: ContentKey(
        ContentKind.book,
        r.read<String>('book_id'),
        r.read<int>('projection_version'),
      ),
      chapterId: r.read<String>('chapter_id'),
      blockId: r.read<String>('block_id'),
      offsetUtf16: r.read<int>('offset_utf16'),
    ),
  );
  Future<T> _write<T>(Future<T> Function() action) {
    final task = _tail.then((_) async {
      try {
        return await db.transaction(action);
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
  Future<BookmarkAdded> add(BookLocator locator) => _write(() async {
    await _ready(locator.key);
    await source.validateReadingBoundary(locator);
    final block = await source.block(locator.key, locator.blockId);
    if (!block.speechEligible || block.text.trim().isEmpty) {
      throw const BookFailure(BookError.invalidLocator);
    }
    final existing = await db
        .customSelect(
          'SELECT * FROM book_bookmarks WHERE book_id=? AND projection_version=? AND chapter_id=? AND block_id=? AND offset_utf16=?',
          variables: [
            Variable(locator.key.id),
            Variable(locator.key.version),
            Variable(locator.chapterId),
            Variable(locator.blockId),
            Variable(locator.offsetUtf16),
          ],
        )
        .get();
    if (existing.isNotEmpty) {
      return BookmarkAdded(_row(existing.single), created: false);
    }
    final id = idFactory(), time = now();
    if (!_validId(id) || time < 0) {
      throw const BookFailure(BookError.invalidContent);
    }
    await db.customStatement(
      'INSERT INTO book_bookmarks VALUES(?,?,?,?,?,?,?)',
      [
        id,
        locator.key.id,
        locator.key.version,
        locator.chapterId,
        locator.blockId,
        locator.offsetUtf16,
        time,
      ],
    );
    return BookmarkAdded(
      Bookmark(id: id, locator: locator, createdAt: time),
      created: true,
    );
  });
  @override
  Future<BookmarkPage> list(
    ContentKey key, {
    BookmarkCursor? after,
    int limit = 50,
  }) async {
    if (limit < 1 ||
        limit > 50 ||
        after != null &&
            (after.key != key || after.createdAt < 0 || !_validId(after.id))) {
      throw const BookFailure(BookError.invalidCursor);
    }
    try {
      await _ready(key);
      final rows = await db
          .customSelect(
            'SELECT * FROM book_bookmarks WHERE book_id=? AND projection_version=? ${after == null ? '' : 'AND (created_at>? OR (created_at=? AND bookmark_id>?))'} ORDER BY created_at,bookmark_id LIMIT ?',
            variables: [
              Variable(key.id),
              Variable(key.version),
              if (after != null) ...[
                Variable(after.createdAt),
                Variable(after.createdAt),
                Variable(after.id),
              ],
              Variable(limit + 1),
            ],
          )
          .get();
      final items = rows.take(limit).map(_row).toList();
      return BookmarkPage(
        items,
        next: rows.length <= limit
            ? null
            : BookmarkCursor(key, items.last.createdAt, items.last.id),
      );
    } on BookFailure {
      rethrow;
    } catch (_) {
      throw const BookFailure(BookError.storageUnavailable);
    }
  }

  @override
  Future<void> remove(String id, ContentKey key) => _write(() async {
    if (!_validId(id) || key.kind != ContentKind.book) {
      throw const BookFailure(BookError.invalidLocator);
    }
    await db.customStatement(
      'DELETE FROM book_bookmarks WHERE bookmark_id=? AND book_id=? AND projection_version=?',
      [id, key.id, key.version],
    );
  });
  @override
  Future<BookmarkResolution> resolve(Bookmark bookmark) async {
    final at = bookmark.locator;
    try {
      await _ready(at.key);
      final rows = await db
          .customSelect(
            'SELECT * FROM book_bookmarks WHERE bookmark_id=? AND book_id=? AND projection_version=?',
            variables: [
              Variable(bookmark.id),
              Variable(at.key.id),
              Variable(at.key.version),
            ],
          )
          .get();
      if (rows.isEmpty) {
        return const BookmarkResolution(BookmarkAvailability.unavailable);
      }
      final stored = _row(rows.single);
      if (stored.locator.blockId != at.blockId ||
          stored.locator.chapterId != at.chapterId ||
          stored.locator.offsetUtf16 != at.offsetUtf16) {
        return BookmarkResolution(
          BookmarkAvailability.invalid,
          chapterId: at.chapterId,
        );
      }
      await source.validateReadingBoundary(at);
      final block = await source.block(at.key, at.blockId);
      if (!block.speechEligible || block.text.trim().isEmpty) {
        return BookmarkResolution(
          BookmarkAvailability.invalid,
          chapterId: at.chapterId,
        );
      }
      return BookmarkResolution(BookmarkAvailability.exact, locator: at);
    } on BookFailure catch (e) {
      if (e.code == BookError.storageUnavailable) rethrow;
      return BookmarkResolution(
        e.code == BookError.sourceUnavailable
            ? BookmarkAvailability.unavailable
            : BookmarkAvailability.invalid,
        chapterId: at.chapterId,
      );
    } catch (_) {
      throw const BookFailure(BookError.storageUnavailable);
    }
  }

  @override
  Future<void> flush() => _tail;
}
