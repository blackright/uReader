import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/book_reader/reader_layout.dart';
import 'package:prototype/features/book_reader/book_paginator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = ContentKey(ContentKind.book, 'book', 1);
  BookBlock block(
    int i,
    String text, {
    BookBlockKind kind = BookBlockKind.paragraph,
  }) => BookBlock(
    key: key,
    chapterId: 'c0',
    id: 'c0-b$i-s0',
    ordinal: i,
    kind: kind,
    text: text,
    speechEligible: kind != BookBlockKind.image,
  );
  test(
    'every source unit appears once across line/page/grapheme boundaries',
    () async {
      final text = ('Bonjour e\u0301 😀 œ et apostrophe : l’été. ' * 150);
      final b = block(0, text);
      final layout = ReaderLayout(
        width: 230,
        height: 220,
        textScaler: TextScaler.linear(1.5),
      );
      final pages = await BookPaginator(layout)
          .paginate(Stream.value(b))
          .toList();
      expect(pages.length, greaterThan(1));
      final all = pages.expand((p) => p.fragments).toList();
      expect(
        all.map((f) => f.block.text.substring(f.startUtf16, f.endUtf16)).join(),
        text,
      );
      var at = 0;
      for (final f in all) {
        expect(f.startUtf16, at);
        at = f.endUtf16;
        expect(layout.validBoundary(text, at), true);
      }
      expect(at, text.length);
      expect(pages.every((p) => p.height <= 220.01), true);
    },
  );
  test(
    'hard line breaks and terminal blank lines keep exact ordered endpoints',
    () async {
      final blocks = [
        block(0, '\n\n'),
        block(1, 'un\n\ndeux\n'),
        block(2, 'fin\u2028'),
        block(3, 'famille 👨‍👩‍👧‍👦 et e\u0301.\n'),
      ];
      final layout = ReaderLayout(width: 220, height: 300);
      final pages = await BookPaginator(layout)
          .paginate(Stream.fromIterable(blocks))
          .toList();
      final source = StringBuffer();
      var expected = pages.first.start;
      for (final page in pages) {
        expect(page.start, expected);
        expected = page.end;
        for (final f in page.fragments) {
          source.write(f.block.text.substring(f.startUtf16, f.endUtf16));
        }
      }
      expect(source.toString(), blocks.map((b) => b.text).join());
      expect(pages.last.end.ordinal, blocks.length);
    },
  );
  test('images, blank blocks and headings still advance flow', () async {
    final blocks = [
      block(0, 'Titre', kind: BookBlockKind.heading),
      block(1, '', kind: BookBlockKind.image),
      block(2, ''),
      block(3, 'Dernier'),
    ];
    final pages = await BookPaginator(ReaderLayout(width: 280, height: 300))
        .paginate(Stream.fromIterable(blocks))
        .toList();
    expect(
      pages.expand((p) => p.fragments).map((f) => f.block.ordinal).toSet(),
      {0, 1, 2, 3},
    );
    expect(pages.last.end.ordinal, 4);
  });
  test('cancelled generation publishes no additional page', () async {
    var cancelled = false;
    final pages = <Object>[];
    try {
      await for (final page
          in BookPaginator(ReaderLayout(width: 200, height: 100)).paginate(
            Stream.value(block(0, 'texte ' * 900)),
            cancelled: () => cancelled,
          )) {
        pages.add(page);
        cancelled = true;
      }
    } catch (_) {}
    expect(pages.length, 1);
  });
  test(
    'long paragraph slices keep one paragraph spacing and exact source text',
    () async {
      final a = BookBlock(
        key: key,
        chapterId: 'c0',
        id: 'c0-b0-s0',
        ordinal: 0,
        kind: BookBlockKind.paragraph,
        text: 'mot ' * 2048,
      );
      final b = BookBlock(
        key: key,
        chapterId: 'c0',
        id: 'c0-b0-s1',
        ordinal: 1,
        kind: BookBlockKind.paragraph,
        text: 'suite ' * 900,
      );
      final pages = await BookPaginator(ReaderLayout(width: 220, height: 240))
          .paginate(Stream.fromIterable([a, b]))
          .toList();
      final fragments = pages.expand((p) => p.fragments).toList();
      expect(
        fragments
            .map((f) => f.block.text.substring(f.startUtf16, f.endUtf16))
            .join(),
        a.text + b.text,
      );
      expect(fragments.where((f) => f.block.id == a.id).last.trailing, 0);
      expect(fragments.where((f) => f.block.id == b.id).first.leading, 0);
      expect(fragments.where((f) => f.startsParagraph).length, 1);
    },
  );
}
