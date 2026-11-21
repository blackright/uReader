import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/bookmarks.dart';
import 'package:prototype/infrastructure/database/bookmark_repository.dart';
import 'package:prototype/infrastructure/database/page_index_repository.dart';
import 'package:prototype/infrastructure/database/book_operation_repository.dart';

import '../../features/book_reader/reader_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ReaderFixture f;
  late BookmarkRepository store;
  setUp(() async {
    f = ReaderFixture();
    await f.open();
    store = BookmarkRepository(f.db, f.content, now: () => 1);
  });
  tearDown(() async {
    await store.flush();
    await f.close();
  });
  BookLocator at(ContentKey k, int n, {int offset = 0}) => BookLocator(
    key: k,
    chapterId: n < 4 ? 'c0' : 'c1',
    blockId: 'b$n',
    offsetUtf16: offset,
  );
  test(
    'ten durable locators across three books, duplicates and stable pagination',
    () async {
      final keys = [await f.book('a'), await f.book('b'), await f.book('c')];
      for (var n = 0; n < 10; n++) {
        await store.add(at(keys[n % 3], n ~/ 3));
      }
      final first = await store.list(keys.first, limit: 2);
      expect(first.items.length, 2);
      expect(first.next, isNotNull);
      final rest = await store.list(keys.first, after: first.next, limit: 2);
      expect(
        {
          ...first.items.map((m) => m.id),
          ...rest.items.map((m) => m.id),
        }.length,
        4,
      );
      final duplicate = await store.add(at(keys.first, 0));
      expect(duplicate.created, isFalse);
      final again = BookmarkRepository(f.db, f.content);
      expect((await again.list(keys[1])).items.length, 3);
      final columns = await f.db
          .customSelect('PRAGMA table_info(book_bookmarks)')
          .get();
      expect(
        columns.map((r) => r.read<String>('name')),
        isNot(contains('page_number')),
      );
    },
  );
  test(
    'invalid offsets, failed commit, FK and targeted idempotent removal',
    () async {
      final a = await f.book('integrity'), b = await f.book('other');
      await expectLater(
        store.add(at(a, 0, offset: 999)),
        throwsA(isA<BookFailure>()),
      );
      final mark = await store.add(at(a, 0));
      final other = await store.add(at(b, 0));
      await store.remove(mark.bookmark.id, b);
      expect((await store.list(a)).items.length, 1);
      await f.db.customStatement(
        "CREATE TRIGGER deny_bookmark BEFORE INSERT ON book_bookmarks BEGIN SELECT RAISE(ABORT,'test commit denied'); END",
      );
      await expectLater(store.add(at(a, 1)), throwsA(isA<BookFailure>()));
      expect((await store.list(a)).items.length, 1);
      await f.db.customStatement('DROP TRIGGER deny_bookmark');
      await store.remove(mark.bookmark.id, a);
      await store.remove(mark.bookmark.id, a);
      expect((await store.list(a)).items, isEmpty);
      expect((await store.list(b)).items.single.id, other.bookmark.id);
      await expectLater(
        f.db.customStatement(
          "INSERT INTO book_bookmarks VALUES('bad','missing',1,'c0','b0',0,1)",
        ),
        throwsA(anything),
      );
    },
  );
  test('cache invalidation preserves bookmarks; deletion rejects new writes and cascades only its book', () async {
    final a = await f.book('deleted'), b = await f.book('retained');
    await store.add(at(a, 0));
    await store.add(at(b, 0));
    final index = PageIndexRepository(f.db);
    final handle = await index.begin(a, 'a' * 64, 1);
    await index.invalidate(handle);
    expect((await store.list(a)).items.length, 1);
    final journal = BookOperationRepository(f.db);
    final op = await journal.beginDeletion(a);
    await expectLater(store.add(at(a, 1)), throwsA(isA<BookFailure>()));
    await journal.finishDeletion(op!);
    expect((await store.list(b)).items.length, 1);
    expect(
      (await f.db.customSelect('SELECT * FROM book_bookmarks').get()).length,
      1,
    );
  });
  test(
    'graphemes and concurrent duplicate writes retain canonical source',
    () async {
      final key = await f.book('clusters', text: 'e\u0301 puis 😀.');
      await expectLater(
        store.add(at(key, 0, offset: 1)),
        throwsA(isA<BookFailure>()),
      );
      final added = await Future.wait([
        store.add(at(key, 0)),
        store.add(at(key, 0)),
      ]);
      expect(added.where((a) => a.created).length, 1);
      expect(added[0].bookmark.id, added[1].bookmark.id);
      expect((await f.content.block(key, 'b0')).text, 'e\u0301 puis 😀.');
      final deleting = BookOperationRepository(f.db).beginDeletion(key);
      final late = store.add(at(key, 1));
      await deleting;
      await expectLater(late, throwsA(isA<BookFailure>()));
    },
  );
  test(
    'edited bookmark to an image is not resolved as an exact text passage',
    () async {
      final key = await f.book('edited-image');
      final added = await store.add(at(key, 0));
      await f.db.customStatement(
        "UPDATE book_blocks SET kind='image',speech_eligible=0,source_text='',text_units=0 WHERE book_id=? AND block_id='b0'",
        [key.id],
      );
      expect(
        (await store.resolve(added.bookmark)).availability,
        BookmarkAvailability.invalid,
      );
    },
  );
}
