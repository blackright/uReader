import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/library/book_removal_service.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';
import 'package:prototype/infrastructure/database/book_operation_repository.dart';
import 'package:prototype/infrastructure/files/book_operation_reconciler.dart';

import '../book_reader/reader_fixture.dart';

void main() {
  test(
    'startup recovery has a bounded batch and leaves the remainder journaled',
    () async {
      final f = ReaderFixture();
      await f.open();
      addTearDown(f.close);
      final journal = BookOperationRepository(f.db),
          books = BookRepository(f.db);
      for (var i = 0; i < 3; i++) {
        await journal.beginDeletion(
          await f.book('batch-$i', blocks: 1, chapters: 1),
        );
      }
      final recovery = BookOperationReconciler(
        books,
        journal,
        f.content.files,
        purgeAudio: (_) async {},
      );
      expect(await recovery.recover(limit: 2), isEmpty);
      expect(await journal.pending(), hasLength(1));
      expect(await recovery.recover(limit: 2), isEmpty);
      expect(await journal.pending(), isEmpty);
      await expectLater(
        recovery.recover(limit: 0),
        throwsA(isA<BookFailure>()),
      );
    },
  );
  test('failed database commit retains a deletion job; recovery cannot resurrect an old import', () async {
    final f = ReaderFixture();
    await f.open();
    addTearDown(f.close);
    final a = await f.book('interrupted'), b = await f.book('untouched');
    final original = File('${f.dir.path}/original.epub');
    await original.writeAsBytes([1, 2, 3]);
    await f.db.customStatement(
      "INSERT INTO book_operations(operation_id,book_id,kind,phase,generation,destination,source_bytes,updated_at) VALUES ('old-import',?,'import','validated',1,?,0,1)",
      [a.id, 'books/${a.id}'],
    );
    for (final key in [a, b]) {
      await f.db.customStatement(
        "INSERT INTO book_positions VALUES (?,'audio',1,'c0','b0',0,1,1)",
        [key.id],
      );
    }
    final repo = BookRepository(f.db), journal = BookOperationRepository(f.db);
    final old = (await journal.pending()).single;
    final purged = <String>[];
    final recovery = BookOperationReconciler(
      repo,
      journal,
      f.content.files,
      purgeAudio: (key) async {
        purged.add(key.id);
      },
    );
    final service = BookRemovalService(
      journal: journal,
      files: f.content.files,
      reconciler: recovery,
      releaseTarget: (_) async {},
    );
    await f.db.customStatement(
      "CREATE TRIGGER reject_delete BEFORE DELETE ON books WHEN OLD.book_id='interrupted' BEGIN SELECT RAISE(ABORT,'injected'); END",
    );
    await expectLater(
      service.remove(a, confirmed: true),
      throwsA(isA<BookFailure>()),
    );
    expect((await journal.pending()).single.kind, BookOperationKind.delete);
    expect((await repo.deletingPage()).single.key, a);
    await expectLater(recovery.publish(old), throwsA(anything));
    expect(await original.readAsBytes(), [1, 2, 3]);
    await f.db.customStatement('DROP TRIGGER reject_delete');
    expect(await recovery.recover(), isEmpty);
    expect((await repo.readyPage()).single.key, b);
    expect(await journal.pending(), isEmpty);
    expect(
      (await f.db.customSelect('SELECT book_id FROM book_positions').get())
          .single
          .read<String>('book_id'),
      b.id,
    );
    expect(purged.every((id) => id == a.id), true);
    expect(await service.remove(a, confirmed: true), true);
    expect(await original.readAsBytes(), [1, 2, 3]);
    await service.close();
  });
  test('recovery keeps a failed purge pending and never publishes its obsolete import', () async {
    final f = ReaderFixture();
    await f.open();
    addTearDown(f.close);
    final key = await f.book('purge-failure');
    final journal = BookOperationRepository(f.db), books = BookRepository(f.db);
    await journal.beginDeletion(key);
    final recovery = BookOperationReconciler(
      books,
      journal,
      f.content.files,
      purgeAudio: (_) async {
        throw const FileSystemException('injected');
      },
    );
    expect(await recovery.recover(), hasLength(1));
    expect(await books.readyPage(), isEmpty);
    expect(await books.deletingPage(), hasLength(1));
    expect(await journal.pending(), hasLength(1));
    expect(await Directory('${f.dir.path}/books/${key.id}').exists(), true);
  });
}
