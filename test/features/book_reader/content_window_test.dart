import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';

import 'reader_fixture.dart';

void main() {
  late ReaderFixture f;
  setUp(() async {
    f = ReaderFixture();
    await f.open();
  });
  tearDown(() async {
    await f.close();
  });
  test(
    'long chapter remains bounded forward, backward and at an anchor',
    () async {
      final key = await f.book(
        'long',
        blocks: 1500,
        chapters: 1,
        text: 'a😀b' * 1024,
      );
      final first = await f.content.window(key, 1);
      expect(first.blocks.length, 16);
      expect(first.blocks.fold<int>(0, (n, b) => n + b.text.length), 65536);
      final target = BookLocator(
        key: key,
        chapterId: 'c0',
        blockId: 'b1000',
        offsetUtf16: 3,
      );
      final jumped = await f.content.windowAt(target, 2);
      expect(jumped.blocks.first.id, 'b1000');
      await f.db.customStatement(
        'INSERT INTO book_anchors VALUES (?,?,?,?,?,?)',
        ['long', 'OPS/c0.xhtml', 'point', 'c0', 'b1000', 3],
      );
      expect(
        (await f.content.resolveAnchor(
          key,
          'OPS/c0.xhtml',
          'point',
        )).offsetUtf16,
        3,
      );
      final previous = await f.content.windowBefore(key, 3, 1000);
      expect(previous.blocks.last.ordinal, 999);
      expect(previous.blocks.length, lessThanOrEqualTo(64));
      expect((await f.content.progress(target)).$1, 1000 * 4096 + 3);
      await expectLater(
        f.content.window(key, 2, after: first.next),
        throwsA(isA<BookFailure>()),
      );
      await expectLater(
        f.content.window(
          ContentKey(ContentKind.book, 'foreign', 1),
          1,
          after: first.next,
        ),
        throwsA(isA<BookFailure>()),
      );
      await expectLater(
        f.content.validateLocator(
          BookLocator(key: key, chapterId: 'c0', blockId: 'b0', offsetUtf16: 2),
        ),
        throwsA(isA<BookFailure>()),
      );
    },
  );
}
