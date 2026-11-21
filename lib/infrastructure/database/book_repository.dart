import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/books.dart';
import '../../domain/app_error.dart' show requireIdentifier;
import '../epub/epub_package_parser.dart';
import 'prototype_database.dart';

enum BookSort { recent, title, author }

/// Drafts are never returned by readyPage. SQL and metadata stay out of widgets.
class BookRepository {
  BookRepository(this.db);
  final PrototypeDatabase db;
  List<Variable> _v(List<Object> values) => values
      .map((v) => v is int ? Variable<int>(v) : Variable<String>(v as String))
      .toList();
  Future<void> begin(String operation, String book, int generation) async {
    requireIdentifier(operation);
    requireIdentifier(book);
    if (generation < 1) throw const BookFailure(BookError.invalidContent);
    await db.transaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db.customStatement(
        "INSERT INTO books(book_id,source_bytes,title,authors_json,languages_json,title_key,author_key,search_key_version,created_at,updated_at,state,projection_version,last_mode) VALUES (?,0,'Livre sans titre','[]','[]','', '',1,?,?,'staging',1,'visual')",
        [book, now, now],
      );
      await db.customStatement(
        "INSERT INTO book_operations(operation_id,book_id,kind,phase,generation,destination,source_bytes,updated_at) VALUES (?,?,'import','copying',?,?,0,?)",
        [operation, book, generation, 'books/$book', now],
      );
    });
  }

  Future<void> _owned(String op, String book, List<String> phases) async {
    final rows = await db
        .customSelect(
          "SELECT o.phase,b.state FROM book_operations o JOIN books b ON b.book_id=o.book_id WHERE o.operation_id=? AND o.book_id=? AND o.kind='import'",
          variables: _v([op, book]),
        )
        .get();
    if (rows.length != 1 ||
        rows.single.read<String>('state') != 'staging' ||
        !phases.contains(rows.single.read<String>('phase'))) {
      throw const BookFailure(BookError.invalidContent);
    }
  }

  Future<Book?> reserve(
    String operation,
    String book,
    String sha,
    int bytes,
  ) async => db.transaction(() async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
        bytes < 0 ||
        bytes > 104857600) {
      throw const BookFailure(BookError.limitExceeded);
    }
    await _owned(operation, book, ['copying']);
    final matches = await db
        .customSelect(
          'SELECT * FROM books WHERE source_sha256=?',
          variables: _v([sha]),
        )
        .get();
    if (matches.isNotEmpty) {
      final row = matches.single;
      if (row.read<String>('state') == 'ready') return _book(row);
      throw const BookFailure(BookError.operationInProgress);
    }
    await db.customStatement(
      'UPDATE books SET source_sha256=?,source_bytes=? WHERE book_id=? AND state=\'staging\'',
      [sha, bytes, book],
    );
    await db.customStatement(
      "UPDATE book_operations SET phase='validating',source_bytes=? WHERE operation_id=?",
      [bytes, operation],
    );
    return null;
  });
  Future<void> metadata(
    String op,
    String book,
    EpubPackage package, {
    required String titleKey,
    required String authorKey,
  }) async {
    await _owned(op, book, ['validating']);
    await db.customStatement(
      'UPDATE books SET title=?,authors_json=?,languages_json=?,title_key=?,author_key=? WHERE book_id=? AND state=\'staging\'',
      [
        package.title,
        jsonEncode(package.authors),
        jsonEncode(package.languages),
        titleKey,
        authorKey,
        book,
      ],
    );
  }

  Future<void> resource(
    String op,
    String book, {
    required String id,
    required String href,
    required String mediaType,
    required int bytes,
    required String sha,
    int? width,
    int? height,
    required bool retained,
  }) async {
    await _owned(op, book, ['validating']);
    requireIdentifier(id);
    if (bytes < 0 ||
        bytes > 52428800 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha)) {
      throw const BookFailure(BookError.limitExceeded);
    }
    await db.customStatement(
      'INSERT INTO book_resources VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        book,
        id,
        href,
        id,
        mediaType,
        bytes,
        sha,
        width,
        height,
        retained ? 'retained' : 'placeholder',
      ],
    );
  }

  Future<void> setCover(String op, String book, String? resourceId) async {
    await _owned(op, book, ['validating']);
    if (resourceId != null) {
      final rows = await db
          .customSelect(
            'SELECT resource_id FROM book_resources WHERE book_id=? AND resource_id=?',
            variables: _v([book, resourceId]),
          )
          .get();
      if (rows.length != 1) throw const BookFailure(BookError.invalidContent);
    }
    await db.customStatement(
      'UPDATE books SET cover_resource_id=? WHERE book_id=?',
      [resourceId, book],
    );
  }

  Future<void> chapter(String op, BookChapter chapter) async {
    await _owned(op, chapter.key.id, ['validating']);
    await db.customStatement(
      'INSERT INTO book_chapters VALUES (?,?,?,?,?,?,?,?)',
      [
        chapter.key.id,
        chapter.id,
        chapter.ordinal,
        chapter.resource,
        chapter.title,
        chapter.firstBlockOrdinal,
        chapter.blockCount,
        chapter.textUnits,
      ],
    );
  }

  Future<void> blocks(
    String op,
    List<BookBlock> blocks, {
    required int firstOrdinal,
    required int unitsBefore,
  }) async {
    if (blocks.isEmpty) return;
    if (blocks.length > 64 ||
        blocks.fold<int>(0, (s, b) => s + b.text.length) > 65536) {
      throw const BookFailure(BookError.limitExceeded);
    }
    final owner = blocks.first.key;
    await db.transaction(() async {
      await _owned(op, owner.id, ['validating']);
      var ordinal = firstOrdinal;
      var before = unitsBefore;
      for (final b in blocks) {
        if (b.key != owner) throw const BookFailure(BookError.invalidContent);
        final spans = b.inline
            .map(
              (i) => {
                'start': i.startUtf16,
                'end': i.endUtf16,
                'strong': i.strong,
                'emphasis': i.emphasis,
                'link': i.link?.target,
              },
            )
            .toList();
        await db.customStatement(
          'INSERT INTO book_blocks VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [
            owner.id,
            b.id,
            b.chapterId,
            ordinal++,
            b.kind.name,
            b.text,
            b.text.length,
            jsonEncode(spans),
            b.speechEligible ? 1 : 0,
            b.speechEligible || b.kind == BookBlockKind.image ? null : b.id,
            b.resourceId,
            b.alternative,
            before,
          ],
        );
        before += b.text.length;
      }
    });
  }

  Future<void> anchors(
    String op,
    String resource,
    Map<String, BookLocator> anchors,
  ) async {
    if (anchors.isEmpty) return;
    await db.transaction(() async {
      await _owned(op, anchors.values.first.key.id, ['validating']);
      for (final entry in anchors.entries) {
        final a = entry.value;
        await db.customStatement(
          'INSERT INTO book_anchors VALUES (?,?,?,?,?,?)',
          [
            a.key.id,
            resource,
            entry.key,
            a.chapterId,
            a.blockId,
            a.offsetUtf16,
          ],
        );
      }
    });
  }

  Future<void> validated(
    String op,
    String book,
    String manifest,
    String proof,
  ) async => db.transaction(() async {
    await _owned(op, book, ['validating']);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(manifest) ||
        utf8.encode(proof).length > 2097152) {
      throw const BookFailure(BookError.limitExceeded);
    }
    final count = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM book_blocks WHERE book_id=?',
          variables: _v([book]),
        )
        .getSingle();
    if (count.read<int>('n') == 0) {
      throw const BookFailure(BookError.invalidContent);
    }
    await db.customStatement(
      'UPDATE books SET manifest_sha256=? WHERE book_id=?',
      [manifest, book],
    );
    await db.customStatement(
      "UPDATE book_operations SET phase='validated',validation_json=? WHERE operation_id=?",
      [proof, op],
    );
  });
  Future<void> commitReady(String op, String book, String manifest) async =>
      db.transaction(() async {
        await _owned(op, book, ['validated']);
        final row = await db
            .customSelect(
              'SELECT manifest_sha256 FROM books WHERE book_id=?',
              variables: _v([book]),
            )
            .getSingle();
        if (row.readNullable<String>('manifest_sha256') != manifest) {
          throw const BookFailure(BookError.invalidContent);
        }
        await db.customStatement(
          "UPDATE books SET state='ready',updated_at=? WHERE book_id=?",
          [DateTime.now().millisecondsSinceEpoch, book],
        );
        await db.customStatement(
          "UPDATE book_operations SET phase='published' WHERE operation_id=?",
          [op],
        );
      });

  /// Never removes another operation, a ready/deleting book, or a reserved winner.
  Future<void> abandon(String op, String book) async =>
      db.transaction(() async {
        final rows = await db
            .customSelect(
              "SELECT o.phase,b.state FROM book_operations o JOIN books b ON b.book_id=o.book_id WHERE o.operation_id=? AND o.book_id=?",
              variables: _v([op, book]),
            )
            .get();
        if (rows.isEmpty) return;
        if (rows.single.read<String>('state') != 'staging' ||
            ![
              'copying',
              'validating',
              'error',
            ].contains(rows.single.read<String>('phase'))) {
          throw const BookFailure(BookError.invalidContent);
        }
        await db.customStatement(
          "DELETE FROM books WHERE book_id=? AND state='staging'",
          [book],
        );
      });
  Book _book(QueryRow row) => Book(
    key: ContentKey(
      ContentKind.book,
      row.read<String>('book_id'),
      row.read<int>('projection_version'),
    ),
    title: row.read<String>('title'),
    authors: List<String>.from(
      jsonDecode(row.read<String>('authors_json')) as List,
    ),
    coverResource: row.readNullable<String>('cover_resource_id'),
    languages: List<String>.from(
      jsonDecode(row.read<String>('languages_json')) as List,
    ),
  );
  Future<({Book book, String? cover})?> playerBook(ContentKey key) async {
    final rows = await db
        .customSelect(
          "SELECT * FROM books WHERE book_id=? AND projection_version=? AND state='ready'",
          variables: [Variable(key.id), Variable(key.version)],
        )
        .get();
    if (rows.isEmpty) return null;
    return (
      book: _book(rows.single),
      cover: rows.single.readNullable<String>('cover_resource_id'),
    );
  }

  Future<List<Book>> readyPage({
    String? afterKey,
    String? afterId,
    String search = '',
    int limit = 50,
    BookSort sort = BookSort.title,
  }) async {
    if (limit < 1 ||
        limit > 50 ||
        search.length > 16384 ||
        (afterKey == null) != (afterId == null)) {
      throw const BookFailure(BookError.limitExceeded);
    }
    final where = <String>["state='ready'"], args = <Object>[];
    final column = switch (sort) {
      BookSort.recent => 'created_at',
      BookSort.title => 'title_key',
      BookSort.author => 'author_key',
    };
    if (search.isNotEmpty) {
      where.add('(instr(title_key,?)>0 OR instr(author_key,?)>0)');
      args.addAll([search, search]);
    }
    if (afterKey != null) {
      final Object key = sort == BookSort.recent
          ? int.tryParse(afterKey) ??
                (throw const BookFailure(BookError.invalidCursor))
          : afterKey;
      where.add(
        '($column${sort == BookSort.recent ? '<' : '>'}? OR ($column=? AND book_id>?))',
      );
      args.addAll([key, key, afterId!]);
    }
    args.add(limit);
    return (await db
            .customSelect(
              'SELECT * FROM books WHERE ${where.join(' AND ')} ORDER BY $column ${sort == BookSort.recent ? 'DESC' : 'ASC'},book_id LIMIT ?',
              variables: _v(args),
            )
            .get())
        .map(_book)
        .toList();
  }

  Future<({List<Book> books, String? nextKey, String? nextId})> page({
    String? afterKey,
    String? afterId,
    String search = '',
    BookSort sort = BookSort.title,
  }) async {
    final books = await readyPage(
      afterKey: afterKey,
      afterId: afterId,
      search: search,
      sort: sort,
    );
    if (books.length < 50) return (books: books, nextKey: null, nextId: null);
    final last = books.last;
    final column = switch (sort) {
      BookSort.recent => 'created_at',
      BookSort.title => 'title_key',
      BookSort.author => 'author_key',
    };
    final row = await db
        .customSelect(
          "SELECT $column FROM books WHERE book_id=? AND state='ready'",
          variables: [Variable(last.key.id)],
        )
        .get();
    if (row.isEmpty) throw const BookFailure(BookError.revisionConflict);
    return (
      books: books,
      nextKey: sort == BookSort.recent
          ? row.single.read<int>(column).toString()
          : row.single.read<String>(column),
      nextId: last.key.id,
    );
  }

  Future<List<Book>> deletingPage() async =>
      (await db
              .customSelect(
                "SELECT * FROM books WHERE state='deleting' ORDER BY created_at,book_id LIMIT 50",
              )
              .get())
          .map(_book)
          .toList();
}
