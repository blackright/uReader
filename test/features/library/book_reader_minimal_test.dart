import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/book_reader/book_reader_screen.dart';

void main() {
  testWidgets(
    'minimal reader replaces the current window and releases its lease',
    (tester) async {
      final key = ContentKey(ContentKind.book, 'book', 1);
      final source = ReaderSource(key);
      await tester.pumpWidget(
        MaterialApp(
          home: BookReaderScreen(
            book: Book(
              key: key,
              title: 'Mon livre',
              authors: [],
              languages: ['en'],
            ),
            content: source,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Premier passage'), findsOneWidget);
      await tester.tap(find.byTooltip('Passages suivants'));
      await tester.pumpAndSettle();
      expect(find.text('Second passage'), findsOneWidget);
      expect(find.text('Premier passage'), findsNothing);
      expect(find.text('Fin du livre'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(source.lease.released, true);
    },
  );
}

class ReaderLease implements ContentLease {
  bool released = false;
  @override
  Future<void> release() async {
    released = true;
  }
}

class ReaderSource implements BookContentSource {
  ReaderSource(this.key);
  final ContentKey key;
  final lease = ReaderLease();
  @override
  Future<ContentLease> acquire(ContentKey key) async => lease;
  @override
  Future<BookWindow> window(
    ContentKey key,
    int generation, {
    BookCursor? after,
    int maxBlocks = 64,
    int maxUnits = 65536,
  }) async {
    final ordinal = after?.nextOrdinal ?? 0;
    return BookWindow(
      key: key,
      generation: generation,
      blocks: [
        BookBlock(
          key: key,
          chapterId: 'c0',
          id: 'b$ordinal',
          ordinal: ordinal,
          kind: BookBlockKind.paragraph,
          text: ordinal == 0 ? 'Premier passage' : 'Second passage',
        ),
      ],
      next: ordinal == 0
          ? BookCursor(key: key, generation: generation, nextOrdinal: 1)
          : null,
    );
  }

  @override
  Future<List<BookChapter>> chapters(ContentKey key) async => [];
  @override
  Future<BookLocator> resolveAnchor(
    ContentKey key,
    String resource,
    String fragment,
  ) async => throw const BookFailure(BookError.invalidLocator);
  @override
  Future<void> validateLocator(BookLocator locator) async {}
}
