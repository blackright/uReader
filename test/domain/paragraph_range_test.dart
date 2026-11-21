import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/book_reader/paragraph_index.dart';

void main() {
  final key = ContentKey(ContentKind.book, 'book', 1);
  BookBlock block(String id, int ordinal, String text, {bool speech = true}) =>
      BookBlock(
        key: key,
        chapterId: 'c0',
        id: id,
        ordinal: ordinal,
        kind: BookBlockKind.paragraph,
        text: text,
        speechEligible: speech,
      );
  test(
    'bounded slices form one logical paragraph, keeping stable locators',
    () {
      final index = ParagraphIndex();
      final a = block('c0-b2-s0', 0, 'a' * 8192),
          b = block('c0-b2-s1', 1, 'suite');
      expect(index.identity(a), index.identity(b));
      expect(index.slice(a), 0);
      expect(index.slice(b), 1);
      final range = index.range(a, b);
      expect(range.start.blockId, a.id);
      expect(range.end.blockId, b.id);
      expect(range.end.offsetUtf16, 5);
      expect(
        index.identity(block('c0-b3-s0', 2, 'autre')),
        isNot(index.identity(a)),
      );
    },
  );
  test('slice ids and compatibility are validated, never guessed', () {
    final index = ParagraphIndex();
    expect(
      () => index.range(block('c0-b1-s1', 0, 'a'), block('c0-b2-s0', 1, 'b')),
      throwsA(isA<BookFailure>()),
    );
    expect(
      () => index.identity(block('c1-b2-s0', 0, 'a')),
      throwsA(isA<BookFailure>()),
    );
    expect(index.identity(block('legacy-block', 0, 'a')), 'legacy-block');
    expect(
      () => index.range(
        block('c0-b2-s0', 0, 'a'),
        block('c0-b2-s1', 1, 'b', speech: false),
      ),
      throwsA(isA<BookFailure>()),
    );
  });
  test('new page offsets respect graphemes, not only surrogate pairs', () {
    final index = ParagraphIndex();
    final b = block('c0-b1-s0', 0, 'e\u0301😀x');
    expect(index.validBoundary(b, 1), false);
    expect(index.validBoundary(b, 3), false);
    expect(index.validBoundary(b, 2), true);
    expect(index.validBoundary(b, 4), true);
  });
}
