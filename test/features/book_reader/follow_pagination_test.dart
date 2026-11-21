import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/book_reader/book_pagination_controller.dart';
import 'package:prototype/features/book_reader/reader_layout.dart';
import 'package:prototype/infrastructure/database/page_index_repository.dart';

import 'reader_fixture.dart';
import 'book_pagination_controller_test.dart' show settled;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('audio follow reuses the index, keeps three pages and rejects a cancelled navigation', () async {
    final f = ReaderFixture();
    await f.open();
    final key = await f.book(
      'follow-pages',
      blocks: 4,
      chapters: 2,
      text: List.filled(30, 'Bonjour le jardin.').join(' '),
    );
    BookLocator? seen;
    final pager = BookPaginationController(
      key: key,
      source: f.content,
      index: PageIndexRepository(f.db),
      onVisible: (at, _) => seen = at,
    );
    try {
      await pager.configure(
        ReaderLayout(width: 240, height: 180),
        BookLocator(key: key, chapterId: 'c0', blockId: 'b0', offsetUtf16: 0),
      );
      await settled(pager);
      expect(pager.calculating, isFalse);
      expect(pager.error, isNull);
      final generation = pager.generation;
      final target = BookLocator(
        key: key,
        chapterId: 'c1',
        blockId: 'b3',
        offsetUtf16: 0,
      );
      expect(await pager.followTo(target, stillCurrent: () => true), isTrue);
      expect(seen!.blockId, 'b3');
      expect(pager.generation, generation);
      expect(pager.retainedPages, lessThanOrEqualTo(3));
      final old = pager.current;
      expect(
        await pager.followTo(
          BookLocator(key: key, chapterId: 'c0', blockId: 'b0', offsetUtf16: 0),
          stillCurrent: () => false,
        ),
        isFalse,
      );
      expect(identical(pager.current, old), isTrue);
    } finally {
      await pager.close();
      await f.close();
    }
  });
}
