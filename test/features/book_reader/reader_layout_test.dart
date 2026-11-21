import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/pagination.dart';
import 'package:prototype/features/book_reader/reader_layout.dart';
import 'package:prototype/features/book_reader/book_paginator.dart';
import 'package:prototype/features/book_reader/book_block_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cooperative measurement matches synchronous geometry and is cancellable',
    () async {
      final block = BookBlock(
        key: ContentKey(ContentKind.book, 'measure', 1),
        chapterId: 'c0',
        id: 'c0-b0-s0',
        ordinal: 0,
        kind: BookBlockKind.paragraph,
        text: 'Bonjour e\u0301 et 😀. Nouvelle ligne.\n' * 180,
      );
      final layout = ReaderLayout(
        width: 160,
        height: 240,
        textScaler: TextScaler.linear(3.2),
      );
      final expected = layout.measure(block);
      final batches = <int>[];
      final actual = await layout.measureCooperatively(
        block,
        cancelled: () => false,
        onBatch: batches.add,
      );
      expect(actual.height, expected.height);
      expect(actual.prefix, expected.prefix);
      expect(
        actual.lines.map((l) => [l.start, l.end, l.top, l.height]).toList(),
        expected.lines.map((l) => [l.start, l.end, l.top, l.height]).toList(),
      );
      expect(batches, isNotEmpty);
      var cancelled = false, yielded = false;
      await expectLater(
        layout.measureCooperatively(
          block,
          cancelled: () => cancelled,
          onBatch: (_) {
            if (!yielded) {
              yielded = true;
              Timer.run(() => cancelled = true);
            }
          },
        ),
        throwsA(
          isA<PaginationFailure>().having(
            (e) => e.code,
            'code',
            PaginationError.cancelled,
          ),
        ),
      );
      expect(cancelled, isTrue);
    },
  );
  for (final scale in [1.0, 3.2]) {
    testWidgets(
      'shared text metrics, styles and link actions at scale $scale',
      (tester) async {
        final key = ContentKey(ContentKind.book, 'book', 1);
        final block = BookBlock(
          key: key,
          chapterId: 'c0',
          id: 'c0-b0-s0',
          ordinal: 0,
          kind: BookBlockKind.quote,
          text: 'Bonjour lien, puis la suite.',
          inline: [
            BookInline(startUtf16: 0, endUtf16: 7, strong: true),
            BookInline(
              startUtf16: 8,
              endUtf16: 12,
              link: BookLink('#note', 8, 12),
            ),
          ],
        );
        final layout = ReaderLayout(
          width: 300,
          height: 500,
          textScaler: TextScaler.linear(scale),
        );
        final pages = (await tester.runAsync(
          () => BookPaginator(layout).paginate(Stream.value(block)).toList(),
        ))!;
        var links = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                height: 500,
                child: Column(
                  children: [
                    for (final f in pages.first.fragments)
                      ReaderFragmentView(
                        layout: layout,
                        fragment: f,
                        onLink: (_, _) => links++,
                        onNote: (_) {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (final f in pages.first.fragments) {
          expect(
            tester.getSize(find.byKey(ValueKey(f.identity))).height,
            closeTo(f.height, .1),
          );
        }
        final semantics = tester.ensureSemantics();
        expect(find.byType(RichText), findsWidgets);
        final rich = find.descendant(
          of: find.byType(ReaderFragmentView).first,
          matching: find.byType(RichText),
        );
        final painter = layout.painter(block)
          ..layout(maxWidth: layout.textWidth(block));
        final rect = painter
            .getBoxesForSelection(
              const TextSelection(baseOffset: 8, extentOffset: 12),
            )
            .first
            .toRect();
        await tester.tapAt(tester.getTopLeft(rich.first) + rect.center);
        expect(links, 1);
        painter.dispose();
        semantics.dispose();
      },
    );
  }
  testWidgets(
    'scroll uses the shared fragment geometry and keeps canonical caret keys',
    (tester) async {
      final key = ContentKey(ContentKind.book, 'shared', 1);
      for (final kind in [
        BookBlockKind.paragraph,
        BookBlockKind.quote,
        BookBlockKind.listItem,
        BookBlockKind.tableCell,
        BookBlockKind.preformatted,
      ]) {
        final block = BookBlock(
          key: key,
          chapterId: 'c0',
          id: 'c0-b0-s0',
          ordinal: 0,
          kind: kind,
          text: 'Un lien et la suite du paragraphe.',
          inline: [
            BookInline(startUtf16: 0, endUtf16: 2, strong: true),
            BookInline(
              startUtf16: 3,
              endUtf16: 7,
              link: BookLink('#cible', 3, 7),
            ),
          ],
        );
        final caret = GlobalKey();
        var links = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 500,
                  child: ListView(
                    children: [
                      BookBlockRenderer(
                        block: block,
                        sharedScrollLayout: true,
                        fontScale: 1.5,
                        lineHeight: 1.8,
                        textKey: caret,
                        onLink: (_, _) => links++,
                        onNote: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        final spec = ReaderLayout(
          width: 300,
          height: 600,
          fontScale: 1.5,
          lineHeight: 1.8,
        );
        final measured = spec.measure(block);
        expect(
          tester.getSize(find.byType(ReaderFragmentView)).height,
          closeTo(measured.height + 16 + measured.prefix, .1),
        );
        final paragraph =
            caret.currentContext!.findRenderObject() as RenderParagraph;
        expect(paragraph.text.toPlainText(), block.text);
        final rect = paragraph
            .getBoxesForSelection(
              const TextSelection(baseOffset: 3, extentOffset: 7),
            )
            .first
            .toRect();
        await tester.tapAt(paragraph.localToGlobal(rect.center));
        expect(links, 1);
        expect(tester.takeException(), isNull);
      }
      final continuation = BookBlock(
        key: key,
        chapterId: 'c0',
        id: 'c0-b0-s1',
        ordinal: 1,
        kind: BookBlockKind.listItem,
        text: 'suite sans nouvelle puce',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: ListView(
                children: [
                  BookBlockRenderer(
                    block: continuation,
                    sharedScrollLayout: true,
                    paragraphEnd: false,
                    onLink: (_, _) {},
                    onNote: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('•'), findsNothing);
      expect(
        tester.getSize(find.byType(ReaderFragmentView)).height,
        closeTo(
          ReaderLayout(width: 300, height: 600).measure(continuation).height,
          .1,
        ),
      );
    },
  );
  test('whole scroll geometry keeps blank lines and terminal breaks', () {
    final layout = ReaderLayout(width: 240, height: 400);
    for (final text in ['', '\n\n', 'ligne\n', 'e\u0301 et 😀\n\nfin']) {
      final block = BookBlock(
        key: ContentKey(ContentKind.book, 'empty', 1),
        chapterId: 'c0',
        id: 'c0-b0-s0',
        ordinal: 0,
        kind: BookBlockKind.paragraph,
        text: text,
      );
      final split = layout.measure(block);
      final whole = layout.measureWholeBlock(block);
      expect(
        whole.height,
        closeTo(
          split.lines.fold<double>(0, (sum, line) => sum + line.height),
          .01,
        ),
      );
    }
  });
  test('unresolved fonts only get an explicitly session-scoped index', () {
    final layout = ReaderLayout(width: 300, height: 500);
    expect(
      () => layout.fingerprint('source', 1),
      throwsA(isA<PaginationFailure>()),
    );
    expect(
      () => layout.fingerprintForSession('source', 1, 'short'),
      throwsA(isA<PaginationFailure>()),
    );
    expect(
      layout.fingerprintForSession('source', 1, 'session-0000000001'),
      isNot(layout.fingerprintForSession('source', 1, 'session-0000000002')),
    );
  });
  test('fingerprint changes with real layout inputs, not color', () {
    expect(
      () => ReaderLayout(width: 300, height: 600).fingerprint('content', 1),
      throwsA(anything),
    );
    final a = ReaderLayout(
      fontRevision: 'resolved-test-fonts',
      width: 300,
      height: 600,
    );
    expect(
      a.fingerprint('content', 1),
      ReaderLayout(
        fontRevision: 'resolved-test-fonts',
        width: 300,
        height: 600,
        color: Colors.white,
      ).fingerprint('content', 1),
    );
    expect(
      a.fingerprint('content', 1),
      isNot(
        ReaderLayout(
          fontRevision: 'resolved-test-fonts',
          width: 301,
          height: 600,
        ).fingerprint('content', 1),
      ),
    );
  });
  testWidgets(
    'all styled fragments keep their shaped glyph boxes inside the visible page',
    (tester) async {
      final key = ContentKey(ContentKind.book, 'styles', 1);
      for (final kind in [
        BookBlockKind.heading,
        BookBlockKind.paragraph,
        BookBlockKind.listItem,
        BookBlockKind.quote,
        BookBlockKind.tableCell,
        BookBlockKind.preformatted,
      ]) {
        final block = BookBlock(
          key: key,
          chapterId: 'c0',
          id: 'c0-b0-s0',
          ordinal: 0,
          kind: kind,
          text: 'Un texte Ã© e\u0301 ðŸ˜€ avec une fin.\nDeuxiÃ¨me ligne.',
        );
        final layout = ReaderLayout(
          width: 280,
          height: 320,
          textScaler: TextScaler.linear(3.2),
        );
        final pages = (await tester.runAsync(
          () => BookPaginator(layout).paginate(Stream.value(block)).toList(),
        ))!;
        for (final fragment in pages.expand((p) => p.fragments)) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: ReaderFragmentView(
                    layout: layout,
                    fragment: fragment,
                    onLink: (_, _) {},
                    onNote: (_) {},
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          final rich = find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == block.text,
          );
          final paragraph = tester.renderObject<RenderParagraph>(rich);
          final bounds = tester
              .getRect(find.byKey(ValueKey(fragment.identity)))
              .inflate(1);
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(
              baseOffset: fragment.startUtf16,
              extentOffset: fragment.endUtf16,
            ),
          );
          for (final box in boxes) {
            final rect = box.toRect().shift(
              paragraph.localToGlobal(Offset.zero),
            );
            expect(rect.top, greaterThanOrEqualTo(bounds.top));
            expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
          }
        }
      }
    },
  );
  testWidgets(
    'new layout preserves accessible note action without exposing note body',
    (tester) async {
      final key = ContentKey(ContentKind.book, 'notes', 1);
      final block = BookBlock(
        key: key,
        chapterId: 'c0',
        id: 'c0-b0-s0',
        ordinal: 0,
        kind: BookBlockKind.paragraph,
        text: 'Corps de note privÃ© au flux principal',
        speechEligible: false,
      );
      final layout = ReaderLayout(width: 280, height: 320);
      var opened = 0;
      final pages = (await tester.runAsync(
        () => BookPaginator(layout).paginate(Stream.value(block)).toList(),
      ))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderFragmentView(
              layout: layout,
              fragment: pages.first.fragments.first,
              onLink: (_, _) {},
              onNote: (_) => opened++,
            ),
          ),
        ),
      );
      expect(find.text(block.text), findsNothing);
      await tester.tap(find.text('Consulter la note'));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
