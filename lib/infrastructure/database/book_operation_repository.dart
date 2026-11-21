import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../domain/books.dart';
import 'prototype_database.dart';

class BookOperationRepository implements BookOperationJournal {
  BookOperationRepository(this.db);
  final PrototypeDatabase db;
  Future<BookOperation?> deletion(String book) async {
    final rows = await db
        .customSelect(
          "SELECT * FROM book_operations WHERE book_id=? AND kind='delete' ORDER BY operation_id LIMIT 1",
          variables: [Variable(book)],
        )
        .get();
    if (rows.isEmpty) return null;
    final r = rows.single;
    return BookOperation(
      id: r.read<String>('operation_id'),
      bookId: book,
      kind: BookOperationKind.delete,
      phase: BookOperationPhase.values.byName(r.read<String>('phase')),
      generation: r.read<int>('generation'),
    );
  }

  Future<BookOperation?> beginDeletion(
    ContentKey key,
  ) => db.transaction(() async {
    if (key.kind != ContentKind.book) {
      throw const BookFailure(BookError.invalidContent);
    }
    final rows = await db
        .customSelect(
          "SELECT state,projection_version FROM books WHERE book_id=?",
          variables: [Variable(key.id)],
        )
        .get();
    if (rows.isEmpty) return null;
    if (rows.length != 1 ||
        rows.single.read<int>('projection_version') != key.version ||
        !['ready', 'deleting'].contains(rows.single.read<String>('state'))) {
      throw const BookFailure(BookError.invalidContent);
    }
    final previous = await deletion(key.id);
    if (previous != null) return previous;
    final now = DateTime.now().microsecondsSinceEpoch;
    final op = BookOperation(
      id: 'delete-$now',
      bookId: key.id,
      kind: BookOperationKind.delete,
      phase: BookOperationPhase.deleting,
      generation: 1,
    );
    await db.customStatement(
      "UPDATE books SET state='deleting' WHERE book_id=?",
      [key.id],
    );
    await db.customStatement(
      "UPDATE book_operations SET phase='error',generation=generation+1 WHERE book_id=? AND kind='import'",
      [key.id],
    );
    await db.customStatement(
      "INSERT INTO book_operations(operation_id,book_id,kind,phase,generation,destination,source_bytes,updated_at) VALUES (?,?,'delete','deleting',1,?,0,?)",
      [op.id, key.id, 'books/${key.id}', DateTime.now().millisecondsSinceEpoch],
    );
    return op;
  });
  Future<ContentKey?> deletionKey(BookOperation op) async {
    final rows = await db
        .customSelect(
          "SELECT b.projection_version FROM books b JOIN book_operations o ON o.book_id=b.book_id WHERE b.book_id=? AND b.state='deleting' AND o.operation_id=? AND o.kind='delete' AND o.generation=?",
          variables: [
            Variable(op.bookId),
            Variable(op.id),
            Variable(op.generation),
          ],
        )
        .get();
    if (rows.isEmpty &&
        (await db
                .customSelect(
                  'SELECT 1 FROM books WHERE book_id=?',
                  variables: [Variable(op.bookId)],
                )
                .get())
            .isNotEmpty) {
      throw const BookFailure(BookError.revisionConflict);
    }
    return rows.isEmpty
        ? null
        : ContentKey(
            ContentKind.book,
            op.bookId,
            rows.single.read<int>('projection_version'),
          );
  }

  Future<void> failDeletion(BookOperation op) => db.customStatement(
    "UPDATE book_operations SET phase='error',error_code='storageUnavailable' WHERE operation_id=? AND kind='delete' AND generation=?",
    [op.id, op.generation],
  );
  Future<List<String>> retiredImports(String book) async =>
      (await db
              .customSelect(
                "SELECT operation_id FROM book_operations WHERE book_id=? AND kind='import' ORDER BY operation_id LIMIT 64",
                variables: [Variable(book)],
              )
              .get())
          .map((r) => r.read<String>('operation_id'))
          .toList();
  Future<void> forgetRetiredImport(String book, String op) =>
      db.customStatement(
        "DELETE FROM book_operations WHERE operation_id=? AND book_id=? AND kind='import' AND EXISTS(SELECT 1 FROM books WHERE book_id=? AND state='deleting')",
        [op, book, book],
      );
  Future<void> finishDeletion(BookOperation op) async {
    await db.customStatement(
      "DELETE FROM books WHERE book_id=? AND state='deleting' AND EXISTS(SELECT 1 FROM book_operations WHERE operation_id=? AND book_id=? AND kind='delete' AND generation=?)",
      [op.bookId, op.id, op.bookId, op.generation],
    );
    if ((await db
            .customSelect(
              'SELECT 1 FROM books WHERE book_id=?',
              variables: [Variable(op.bookId)],
            )
            .get())
        .isNotEmpty) {
      throw const BookFailure(BookError.revisionConflict);
    }
  }

  Future<bool> canPublish(BookOperation op) async =>
      (await db
              .customSelect(
                "SELECT 1 FROM book_operations o JOIN books b ON b.book_id=o.book_id WHERE o.operation_id=? AND o.generation=? AND o.phase='validated' AND o.kind='import' AND b.state='staging'",
                variables: [Variable(op.id), Variable(op.generation)],
              )
              .get())
          .isNotEmpty;
  @override
  Future<List<BookOperation>> pending({int? limit}) async {
    if (limit != null && (limit < 1 || limit > 64)) {
      throw const BookFailure(BookError.limitExceeded);
    }
    return (await db
            .customSelect(
              "SELECT * FROM book_operations WHERE phase!='published' ORDER BY ${limit == null ? '' : "CASE WHEN kind='delete' THEN 0 ELSE 1 END,"}updated_at,operation_id${limit == null ? '' : ' LIMIT ?'}",
              variables: limit == null ? [] : [Variable(limit)],
            )
            .get())
        .map(
          (r) => BookOperation(
            id: r.read<String>('operation_id'),
            bookId: r.read<String>('book_id'),
            kind: BookOperationKind.values.byName(r.read<String>('kind')),
            phase: BookOperationPhase.values.byName(r.read<String>('phase')),
            generation: r.read<int>('generation'),
          ),
        )
        .toList();
  }

  @override
  Future<void> record(BookOperation op) async {
    final n = await db.customUpdate(
      'UPDATE book_operations SET phase=?,updated_at=? WHERE operation_id=? AND book_id=? AND generation=?',
      variables: [
        Variable(op.phase.name),
        Variable(DateTime.now().millisecondsSinceEpoch),
        Variable(op.id),
        Variable(op.bookId),
        Variable(op.generation),
      ],
    );
    if (n != 1) throw const BookFailure(BookError.revisionConflict);
  }

  @override
  Future<void> forget(String operationId) async {
    await db.customStatement(
      "DELETE FROM book_operations WHERE operation_id=? AND phase='published'",
      [operationId],
    );
  }

  Future<void> fail(BookOperation op, BookError code) async {
    await db.customStatement(
      "UPDATE book_operations SET phase='error',error_code=?,updated_at=? WHERE operation_id=? AND book_id=? AND generation=? AND kind='import' AND phase='validated' AND EXISTS(SELECT 1 FROM books b WHERE b.book_id=book_operations.book_id AND b.state='staging')",
      [
        code.name,
        DateTime.now().millisecondsSinceEpoch,
        op.id,
        op.bookId,
        op.generation,
      ],
    );
  }

  /// Claim cleanup durably before touching files: a late publisher then cannot
  /// transition this draft to ready. A ready book is never a cleanup candidate.
  Future<bool> claimCleanup(BookOperation op) async => db.transaction(() async {
    final rows = await db
        .customSelect(
          "SELECT b.state,o.phase FROM book_operations o JOIN books b ON b.book_id=o.book_id WHERE o.operation_id=? AND o.book_id=? AND o.generation=? AND o.kind='import'",
          variables: [
            Variable(op.id),
            Variable(op.bookId),
            Variable(op.generation),
          ],
        )
        .get();
    if (rows.isEmpty) {
      return false;
    }
    if (!['staging', 'deleting'].contains(rows.single.read<String>('state')) ||
        ![
          'copying',
          'validating',
          'error',
        ].contains(rows.single.read<String>('phase'))) {
      return false;
    }
    await db.customStatement(
      "UPDATE books SET state='deleting' WHERE book_id=?",
      [op.bookId],
    );
    await db.customStatement(
      "UPDATE book_operations SET phase='error',error_code=coalesce(error_code,'sourceUnavailable') WHERE operation_id=?",
      [op.id],
    );
    return true;
  });
  Future<void> finishCleanup(BookOperation op) async {
    await db.customStatement(
      "DELETE FROM books WHERE book_id=? AND state='deleting' AND EXISTS(SELECT 1 FROM book_operations o WHERE o.operation_id=? AND o.book_id=books.book_id AND o.generation=? AND o.kind='import' AND o.phase='error')",
      [op.bookId, op.id, op.generation],
    );
  }

  Future<String> canonicalDigest(String book) async {
    final output = _Digest();
    final sink = sha256.startChunkedConversion(output);
    try {
      for (final table in [
        'books',
        'book_chapters',
        'book_blocks',
        'book_anchors',
        'book_resources',
      ]) {
        // Explicit stable columns exclude lifecycle fields changed by final publication.
        final columns = table == 'books'
            ? 'book_id,source_sha256,source_bytes,title,authors_json,languages_json,title_key,author_key,search_key_version,cover_resource_id,projection_version'
            : '*';
        final order = switch (table) {
          'books' => 'book_id',
          'book_chapters' => 'ordinal',
          'book_blocks' => 'ordinal',
          'book_anchors' => 'resource_href,fragment',
          _ => 'resource_id',
        };
        var offset = 0;
        while (true) {
          final rows = await db
              .customSelect(
                'SELECT $columns FROM $table WHERE book_id=? ORDER BY $order LIMIT 64 OFFSET ?',
                variables: [Variable(book), Variable(offset)],
              )
              .get();
          for (final row in rows) {
            sink.add(utf8.encode(jsonEncode([table, row.data])));
            sink.add([10]);
          }
          if (rows.length < 64) break;
          offset += rows.length;
        }
      }
    } finally {
      sink.close();
    }
    return output.value!.toString();
  }

  Future<Map<String, Object?>> proof(String op, String book) async {
    final row = await db
        .customSelect(
          "SELECT o.validation_json,b.manifest_sha256,b.source_sha256 FROM book_operations o JOIN books b ON b.book_id=o.book_id WHERE o.operation_id=? AND o.book_id=? AND o.phase='validated' AND b.state='staging'",
          variables: [Variable(op), Variable(book)],
        )
        .getSingle();
    return row.data;
  }
}

class _Digest implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest d) {
    value = d;
  }

  @override
  void close() {}
}
