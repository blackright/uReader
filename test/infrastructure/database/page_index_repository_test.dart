import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/database/page_index_repository.dart';

import '../../features/book_reader/reader_fixture.dart';

import 'package:prototype/domain/pagination.dart';

void main() {
  late ReaderFixture fixture;
  late PageIndexRepository repository;
  setUp(() async {
    fixture = ReaderFixture();
    await fixture.open();
    repository = PageIndexRepository(fixture.db);
  });
  tearDown(() => fixture.close());
  test(
    'checkpoint and boundaries are atomic, total unknown until completion',
    () async {
      final key = await fixture.book('index');
      final run = await repository.begin(key, 'a' * 64, 1);
      final page = PageBoundary(
        ordinal: 0,
        start: PagePoint(0, 0),
        end: PagePoint(8, 0),
      );
      await repository.append(run, [page], generation: 1, complete: false);
      expect((await repository.read(run))!.total, isNull);
      await repository.append(run, [], generation: 1, complete: true);
      expect((await repository.read(run))!.total, 1);
      expect((await repository.boundaries(run, 0)).length, 1);
    },
  );
  test(
    'failed batch leaves no checkpoint and stale generations cannot publish',
    () async {
      final key = await fixture.book('rollback');
      final run = await repository.begin(key, 'b' * 64, 1);
      await fixture.db.customStatement(
        "CREATE TRIGGER block_pages BEFORE INSERT ON book_page_boundaries BEGIN SELECT RAISE(ABORT,'test'); END",
      );
      await expectLater(
        repository.append(
          run,
          [
            PageBoundary(
              ordinal: 0,
              start: PagePoint(0, 0),
              end: PagePoint(1, 0),
            ),
          ],
          generation: 1,
          complete: false,
        ),
        throwsA(anything),
      );
      expect((await repository.read(run))!.prefixPages, 0);
      await fixture.db.customStatement('DROP TRIGGER block_pages');
      await repository.begin(key, 'b' * 64, 2);
      await expectLater(
        repository.append(run, [], generation: 1, complete: true),
        throwsA(anything),
      );
    },
  );
  test('corrupt cache is rebuilt without losing bookmarks and LRU keeps two layouts', () async {
    final key = await fixture.book('lru');
    await fixture.db.customStatement(
      "INSERT INTO book_bookmarks VALUES('mark',?,1,'c0','b0',0,1)",
      [key.id],
    );
    final bad = await repository.begin(key, 'a' * 64, 1);
    await fixture.db.customStatement(
      "UPDATE book_page_runs SET checkpoint_json='bad'",
    );
    expect(await repository.read(bad), isNull);
    final good = await repository.begin(key, 'a' * 64, 1);
    expect(await repository.read(good), isNotNull);
    await repository.begin(key, 'b' * 64, 1);
    await repository.begin(key, 'c' * 64, 1);
    expect(await repository.read(good), isNull);
    expect(
      (await fixture.db.customSelect('SELECT * FROM book_page_runs').get())
          .length,
      2,
    );
    expect(
      (await fixture.db.customSelect('SELECT * FROM book_bookmarks').get())
          .length,
      1,
    );
  });
  test(
    'persistent checkpoint survives reopen; ownership changes on resumed claim',
    () async {
      final key = await fixture.book('resume');
      final run = await repository.begin(key, 'd' * 64, 1);
      await repository.append(
        run,
        [
          PageBoundary(
            ordinal: 0,
            start: PagePoint(0, 0),
            end: PagePoint(1, 0),
          ),
        ],
        generation: 1,
        complete: false,
      );
      final file = File('${fixture.dir.path}/index-copy.sqlite');
      await fixture.db.customStatement('VACUUM INTO ?', [file.path]);
      final reopened = PrototypeDatabase(NativeDatabase(file));
      try {
        await reopened.initialize();
        final next = PageIndexRepository(reopened);
        final claimed = await next.begin(key, 'd' * 64, 1);
        expect(await next.read(run), isNull);
        expect((await next.read(claimed))!.checkpoint, PagePoint(1, 0));
        await next.append(
          claimed,
          [
            PageBoundary(
              ordinal: 1,
              start: PagePoint(1, 0),
              end: PagePoint(8, 0),
            ),
          ],
          generation: 1,
          complete: true,
        );
        expect((await next.read(claimed))!.total, 2);
      } finally {
        await reopened.close();
      }
    },
  );
  test(
    'early completion and foreign source endpoints cannot invent a total',
    () async {
      final key = await fixture.book('incomplete');
      final run = await repository.begin(key, 'e' * 64, 1);
      await expectLater(
        repository.append(
          run,
          [
            PageBoundary(
              ordinal: 0,
              start: PagePoint(0, 0),
              end: PagePoint(1, 0),
            ),
          ],
          generation: 1,
          complete: true,
        ),
        throwsA(anything),
      );
      expect((await repository.read(run))!.prefixPages, 0);
      await expectLater(
        repository.append(
          run,
          [
            PageBoundary(
              ordinal: 0,
              start: PagePoint(0, 0),
              end: PagePoint(999, 0),
            ),
          ],
          generation: 1,
          complete: false,
        ),
        throwsA(anything),
      );
      expect((await repository.read(run))!.total, isNull);
    },
  );
}
