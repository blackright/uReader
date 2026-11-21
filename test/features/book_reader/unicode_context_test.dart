import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/pagination.dart';
import 'package:prototype/features/book_reader/book_paginator.dart';
import 'package:prototype/features/book_reader/reader_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final key = ContentKey(ContentKind.book, 'unicode-context', 1);
  BookBlock slice(int i, String text, {List<BookInline> inline = const []}) =>
      BookBlock(
        key: key,
        chapterId: 'c0',
        id: 'c0-b0-s$i',
        ordinal: i,
        kind: BookBlockKind.paragraph,
        text: text,
        inline: inline,
      );
  for (final sample in [
    (left: 'e', right: '\u0301'),
    (left: '👨‍', right: '👩‍👧‍👦'),
    (left: '🇫', right: '🇷'),
  ]) {
    test(
      'cross-slice grapheme ${sample.left} exact coverage and cache reconstruction',
      () async {
        final a = slice(
              0,
              ('mot ' * 2048).substring(0, 8192 - sample.left.length) +
                  sample.left,
            ),
            b = slice(1, sample.right + ' suite' * 1000);
        final layout = ReaderLayout(width: 230, height: 260);
        final paginator = BookPaginator(layout);
        final pages = await paginator
            .paginate(Stream.fromIterable([a, b]))
            .toList();
        expect(pages.length, greaterThan(3));
        final fragments = pages.expand((p) => p.fragments).toList();
        expect(
          fragments
              .map((f) => f.block.text.substring(f.startUtf16, f.endUtf16))
              .join(),
          a.text + b.text,
        );
        final text = a.text + b.text;
        var previous = pages.first.start;
        for (final page in pages) {
          expect(page.start, previous);
          previous = page.end;
          final globalStart = page.start.ordinal == 0
              ? page.start.offsetUtf16
              : a.text.length + page.start.offsetUtf16;
          expect(layout.validBoundary(text, globalStart), isTrue);
          expect(page.height, lessThanOrEqualTo(layout.height + .001));
        }
        expect(fragments.where((f) => f.leading > 0).length, 1);
        expect(fragments.where((f) => f.trailing > 0).length, 1);
        // Recreate beginning, seam and late pages exactly from a stored source boundary.
        for (final page in [
          pages[1],
          pages[pages.length ~/ 2],
          pages[pages.length - 2],
        ]) {
          final restored = await BookPaginator(layout)
              .paginate(
                Stream.fromIterable([a, b]),
                from: page.start,
                startPage: page.ordinal,
              )
              .first;
          expect(restored.start, page.start);
          expect(restored.end, page.end);
        }
        final file = File('validation/reader/reports/unicode-host-budget.json');
        await file.parent.create(recursive: true);
        await file.writeAsString(
          jsonEncode({
            'device': 'Flutter host test, not Android',
            'targetMicros': 8000,
            'maximumBatchMicros': paginator.maximumBatchMicros,
            'pages': pages.length,
            'contextUtf16': text.length,
            'note': 'Native shaping cannot be preempted. This is an observation, not an 8ms guarantee.',
          }),
        );
      },
    );
  }
  testWidgets('cross-slice shaping paints once and keeps link origin', (
    tester,
  ) async {
    final a = slice(0, 'e'),
        b = slice(
          1,
          '\u0301 suite',
          inline: [
            BookInline(
              startUtf16: 0,
              endUtf16: 7,
              emphasis: true,
              link: BookLink('https://example.org/', 0, 7),
            ),
          ],
        );
    final layout = ReaderLayout(width: 300, height: 260);
    final pages = (await tester.runAsync(
      () =>
          BookPaginator(layout).paginate(Stream.fromIterable([a, b])).toList(),
    ))!;
    final fragments = pages.single.fragments;
    expect(fragments.length, 2);
    expect(fragments.last.coverageOnly, isTrue);
    BookBlock? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final f in fragments)
                ReaderFragmentView(
                  layout: layout,
                  fragment: f,
                  onLink: (block, _) => opened = block,
                  onNote: (_) {},
                ),
            ],
          ),
        ),
      ),
    );
    final rich = find
        .byType(RichText)
        .evaluate()
        .map((e) => (e.widget as RichText))
        .where((w) => w.text.toPlainText() == 'e\u0301 suite')
        .single;
    final children = (rich.text as TextSpan).children!.cast<TextSpan>();
    final linkSpan = children.last;
    (linkSpan.recognizer as dynamic).onTap();
    expect(opened, same(b));
    expect(tester.takeException(), isNull);
  });
  test(
    'cluster extending past two slices stays a bounded explicit fallback',
    () async {
      await expectLater(
        BookPaginator(ReaderLayout(width: 250, height: 300))
            .paginate(
              Stream.fromIterable([
                slice(0, 'e'),
                slice(1, '\u0301'),
                slice(2, '\u0301 suite'),
              ]),
            )
            .toList(),
        throwsA(
          isA<PaginationFailure>().having(
            (f) => f.code,
            'code',
            PaginationError.unsafeSliceBoundary,
          ),
        ),
      );
    },
  );
}
