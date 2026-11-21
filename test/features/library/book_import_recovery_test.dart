import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';
import 'package:prototype/infrastructure/database/book_operation_repository.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';
import 'package:prototype/infrastructure/files/book_operation_reconciler.dart';

void main() {
  for (final alreadyRenamed in [false, true]) {
    test(
      'recovers validated data after ${alreadyRenamed ? 'rename' : 'validation'} without touching other books',
      () async {
        final dir = await Directory.systemTemp.createTemp('epub-recovery-');
        addTearDown(() => dir.delete(recursive: true));
        final db = PrototypeDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final books = BookRepository(db), journal = BookOperationRepository(db);
        final files = await BookFileStore.open(dir);
        await books.begin('op', 'book', 1);
        final source = [1, 2, 3];
        final sha = sha256.convert(source).toString();
        await books.reserve('op', 'book', sha, 3);
        final key = ContentKey(ContentKind.book, 'book', 1);
        await books.chapter(
          'op',
          BookChapter(
            key: key,
            id: 'c0',
            ordinal: 0,
            title: 'Chapter',
            resource: 'ch.xhtml',
            firstBlockOrdinal: 0,
            blockCount: 1,
            textUnits: 3,
          ),
        );
        await books.blocks(
          'op',
          [
            BookBlock(
              key: key,
              chapterId: 'c0',
              id: 'b0',
              ordinal: 0,
              kind: BookBlockKind.paragraph,
              text: 'ABC',
            ),
          ],
          firstOrdinal: 0,
          unitsBefore: 0,
        );
        await files.writeStaged(
          'op',
          'source',
          Stream.value(source),
          maxBytes: 3,
        );
        final manifest = jsonEncode({
          'version': 1,
          'book': 'book',
          'operation': 'op',
          'sourceSha': sha,
          'canonicalSha': await journal.canonicalDigest('book'),
          'files': [
            {'id': 'source', 'sha': sha, 'bytes': 3},
          ],
        });
        final bytes = utf8.encode(manifest);
        await files.writeStaged(
          'op',
          'manifest',
          Stream.value(bytes),
          maxBytes: bytes.length,
        );
        await books.validated(
          'op',
          'book',
          sha256.convert(bytes).toString(),
          manifest,
        );
        if (alreadyRenamed) await files.publish('op', 'book');
        await BookOperationReconciler(books, journal, files).recover();
        expect((await books.readyPage()).single.key.id, 'book');
        await BookOperationReconciler(books, journal, files).recover();
        expect((await books.readyPage()).length, 1);
      },
    );
  }
  test('an orphan directory creates no book', () async {
    final dir = await Directory.systemTemp.createTemp('epub-orphan-');
    addTearDown(() => dir.delete(recursive: true));
    final files = await BookFileStore.open(dir);
    await files.writeStaged('orphan', 'source', Stream.value([1]), maxBytes: 1);
    await files.publish('orphan', 'orphan');
    final db = PrototypeDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final books = BookRepository(db);
    await BookOperationReconciler(
      books,
      BookOperationRepository(db),
      files,
    ).recover();
    expect(await books.readyPage(), isEmpty);
    expect(await (await files.bookFile('orphan', 'source')).exists(), true);
  });
}
