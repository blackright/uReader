import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';

import '../../features/book_reader/reader_fixture.dart';

void main() {
  late ReaderFixture f;
  late ContentKey key;
  setUp(() async {
    f = ReaderFixture();
    await f.open();
    key = await f.book('paragraphs', blocks: 6, chapters: 1, text: 'abc');
    for (var i = 0; i < 6; i++) {
      final id = i < 3 ? 'c0-b0-s$i' : 'c0-b${i - 2}-s0';
      await f.db.customStatement(
        'UPDATE book_blocks SET block_id=? WHERE book_id=? AND ordinal=?',
        [id, key.id, i],
      );
    }
  });
  tearDown(() => f.close());
  test(
    'a middle slice resolves whole paragraph; pages advance by paragraph',
    () async {
      final locator = BookLocator(
        key: key,
        chapterId: 'c0',
        blockId: 'c0-b0-s1',
        offsetUtf16: 1,
      );
      final range = await f.content.paragraphAt(locator);
      expect(range.start.blockId, 'c0-b0-s0');
      expect(range.end.blockId, 'c0-b0-s2');
      final page = await f.content.paragraphs(key, 4, limit: 2);
      expect(page.paragraphs.map((r) => r.id), ['c0-b0', 'c0-b1']);
      expect(page.nextOrdinal, 4);
      final next = await f.content.paragraphs(
        key,
        4,
        after: BookCursor(
          key: key,
          generation: 4,
          nextOrdinal: page.nextOrdinal!,
        ),
        limit: 2,
      );
      expect(next.paragraphs.map((r) => r.id), ['c0-b2', 'c0-b3']);
      expect(next.nextOrdinal, isNull);
      expect(await f.content.progress(locator), (4, 18));
    },
  );
  test(
    'stale cursor, cursor inside paragraph and invalid limits refused',
    () async {
      await expectLater(
        f.content.paragraphs(
          key,
          2,
          after: BookCursor(key: key, generation: 1, nextOrdinal: 0),
        ),
        throwsA(isA<BookFailure>()),
      );
      await expectLater(
        f.content.paragraphs(
          key,
          1,
          after: BookCursor(key: key, generation: 1, nextOrdinal: 1),
        ),
        throwsA(isA<BookFailure>()),
      );
      await expectLater(
        f.content.paragraphs(key, 1, limit: 51),
        throwsA(isA<BookFailure>()),
      );
    },
  );
  test('corrupt intermediate slice is not silently joined', () async {
    await f.db.customStatement(
      "UPDATE book_blocks SET speech_eligible=0 WHERE book_id=? AND ordinal=1",
      [key.id],
    );
    await expectLater(
      f.content.paragraphAt(
        BookLocator(
          key: key,
          chapterId: 'c0',
          blockId: 'c0-b0-s0',
          offsetUtf16: 0,
        ),
      ),
      throwsA(isA<BookFailure>()),
    );
  });
  test(
    'combining grapheme boundary is stricter than legacy surrogate check',
    () async {
      await f.db.customStatement(
        "UPDATE book_blocks SET source_text=?,text_units=? WHERE book_id=? AND ordinal=3",
        ['e\u0301x', 3, key.id],
      );
      await expectLater(
        f.content.validateReadingBoundary(
          BookLocator(
            key: key,
            chapterId: 'c0',
            blockId: 'c0-b1-s0',
            offsetUtf16: 1,
          ),
        ),
        throwsA(isA<BookFailure>()),
      );
    },
  );
  test(
    'grapheme split at a slice boundary cannot become a page/word boundary',
    () async {
      await f.db.customStatement(
        'UPDATE book_blocks SET source_text=?,text_units=? WHERE book_id=? AND ordinal=0',
        ['e', 1, key.id],
      );
      await f.db.customStatement(
        'UPDATE book_blocks SET source_text=?,text_units=? WHERE book_id=? AND ordinal=1',
        ['\u0301x', 2, key.id],
      );
      for (final locator in [
        BookLocator(
          key: key,
          chapterId: 'c0',
          blockId: 'c0-b0-s0',
          offsetUtf16: 1,
        ),
        BookLocator(
          key: key,
          chapterId: 'c0',
          blockId: 'c0-b0-s1',
          offsetUtf16: 0,
        ),
      ]) {
        await expectLater(
          f.content.validateReadingBoundary(locator),
          throwsA(isA<BookFailure>()),
        );
      }
    },
  );
  test('v3 bookmark uniqueness and cascades preserve another book', () async {
    final other = await f.book('other', blocks: 1, chapters: 1);
    await f.db.customStatement(
      "INSERT INTO book_bookmarks VALUES('one',?,1,'c0','c0-b0-s0',0,1)",
      [key.id],
    );
    await f.db.customStatement(
      "INSERT INTO book_bookmarks VALUES('two',?,1,'c0','b0',0,1)",
      [other.id],
    );
    await expectLater(
      f.db.customStatement(
        "INSERT INTO book_bookmarks VALUES('duplicate',?,1,'c0','c0-b0-s0',0,1)",
        [key.id],
      ),
      throwsA(anything),
    );
    await f.db.customStatement('DELETE FROM books WHERE book_id=?', [key.id]);
    expect(
      (await f.db
              .customSelect('SELECT bookmark_id FROM book_bookmarks')
              .getSingle())
          .read<String>('bookmark_id'),
      'two',
    );
    expect(await f.db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
}
