import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';

void main() {
  ContentKey key([String id = 'book1', int version = 1]) =>
      ContentKey(ContentKind.book, id, version);
  BookBlock block(int ordinal, {String text = 'Bonjour'}) => BookBlock(
    key: key(),
    chapterId: 'c0',
    id: 'c0-b$ordinal-s0',
    ordinal: ordinal,
    kind: BookBlockKind.paragraph,
    text: text,
  );
  test('demo/book identities and versions remain distinct', () {
    expect(key(), isNot(ContentKey(ContentKind.demo, 'book1', 1)));
    expect(key(), isNot(key('book1', 2)));
    expect(key(), key());
    expect(() => key('book1', 0), throwsA(isA<BookFailure>()));
    final book = Book(
      key: key(),
      title: 'English book',
      authors: [],
      languages: ['en'],
    );
    expect(book.languages, ['en']);
  });
  test('windows enforce identity, block and UTF16 quotas', () {
    expect(
      () => BookWindow(
        key: key(),
        generation: 1,
        blocks: List.generate(65, block),
      ),
      throwsA(isA<BookFailure>()),
    );
    expect(
      () => BookWindow(
        key: key(),
        generation: 1,
        blocks: List.generate(9, (i) => block(i, text: 'a' * 8192)),
      ),
      throwsA(isA<BookFailure>()),
    );
    expect(
      () => BookWindow(key: key('other'), generation: 1, blocks: [block(0)]),
      throwsA(isA<BookFailure>()),
    );
    expect(() => block(0, text: 'a' * 8193), throwsA(isA<BookFailure>()));
    expect(
      BookWindow(key: key(), generation: 1, blocks: [block(0)]).done,
      isTrue,
    );
  });
  test('locators reject foreign content and split surrogate pairs', () {
    final b = block(0, text: 'A😀B');
    BookLocator(
      key: key(),
      chapterId: 'c0',
      blockId: b.id,
      offsetUtf16: 3,
    ).validate(b);
    for (final locator in [
      BookLocator(key: key(), chapterId: 'c0', blockId: b.id, offsetUtf16: 2),
      BookLocator(
        key: key('foreign'),
        chapterId: 'c0',
        blockId: b.id,
        offsetUtf16: 0,
      ),
      BookLocator(key: key(), chapterId: 'c1', blockId: b.id, offsetUtf16: 0),
    ]) {
      expect(() => locator.validate(b), throwsA(isA<BookFailure>()));
    }
  });
  test('cursors bind content, projection and generation', () {
    final cursor = BookCursor(key: key(), generation: 2, nextOrdinal: 4);
    expect(() => cursor.validate(key(), 3), throwsA(isA<BookFailure>()));
    expect(
      () => cursor.validate(key('book1', 2), 2),
      throwsA(isA<BookFailure>()),
    );
    cursor.validate(key(), 2);
  });
  test('failures disclose only public French categories', () {
    expect(
      const BookFailure(BookError.limitExceeded).toString(),
      'Le livre dépasse les limites autorisées.',
    );
    expect(
      () => BookLink('javascript:alert(1)', 0, 1),
      throwsA(isA<BookFailure>()),
    );
    expect(
      BookLink('chapter2.xhtml#passage', 0, 2).target,
      'chapter2.xhtml#passage',
    );
  });
}
