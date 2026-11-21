import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/pagination.dart';
import 'package:prototype/features/book_reader/paged_book_view.dart';
import 'package:prototype/features/book_reader/reader_layout.dart';

void main() {
  testWidgets(
    'prefetch leaves chrome focus alone; navigation and reflow return to passage',
    (tester) async {
      final layout = ReaderLayout(width: 300, height: 300);
      BookPage page(int n) {
        final b = BookBlock(
          key: ContentKey(ContentKind.book, 'focus', 1),
          chapterId: 'c0',
          id: 'c0-b$n-s0',
          ordinal: n,
          kind: BookBlockKind.paragraph,
          text: 'Passage $n.',
        );
        final m = layout.measure(b);
        return BookPage(n, [
          PageFragment(
            block: b,
            startUtf16: 0,
            endUtf16: b.text.length,
            clipTop: 0,
            textHeight: m.height,
            fullTextHeight: m.height,
            leading: 8,
            trailing: 8,
          ),
        ]);
      }

      final pages = [page(0), page(1)];
      final chrome = FocusNode(debugLabel: 'Chrome de lecture');
      late StateSetter update;
      var index = 0, prefetched = false, generation = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      focusNode: chrome,
                      onPressed: () => setState(() => index = 1),
                      child: const Text('Avancer'),
                    ),
                    PagedBookView(
                      layout: layout,
                      generation: generation,
                      current: pages[index],
                      previous: index == 1 ? pages[0] : null,
                      next: index == 0 && prefetched ? pages[1] : null,
                      onPrevious: () => setState(() => index = 0),
                      onNext: () => setState(() => index = 1),
                      onLink: (_, _) {},
                      onNote: (_) {},
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      chrome.requestFocus();
      await tester.pump();
      update(() => prefetched = true);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(chrome));
      await tester.tap(find.text('Avancer'));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus!.debugLabel, 'Passage paginé');
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pumpAndSettle();
      expect(index, 0);
      chrome.requestFocus();
      await tester.pump();
      update(() => generation++);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus!.debugLabel, 'Passage paginé');
      await tester.pumpWidget(const SizedBox());
      chrome.dispose();
    },
  );
  for (final reduced in [false, true]) {
    testWidgets('twenty turns, boundaries and semantics, reduced=$reduced', (
      tester,
    ) async {
      final layout = ReaderLayout(width: 300, height: 300);
      final pages = <BookPage>[];
      for (var i = 0; i < 5; i++) {
        final b = BookBlock(
          key: ContentKey(ContentKind.book, 'turn', 1),
          chapterId: 'c0',
          id: 'c0-b$i-s0',
          ordinal: i,
          kind: BookBlockKind.paragraph,
          text: 'Passage numéro $i.',
        );
        final measured = layout.measure(b);
        pages.add(
          BookPage(i, [
            PageFragment(
              block: b,
              startUtf16: 0,
              endUtf16: b.text.length,
              clipTop: 0,
              textHeight: measured.height,
              fullTextHeight: measured.height,
              leading: 8,
              trailing: 8,
            ),
          ]),
        );
      }
      var index = 0, turns = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: StatefulBuilder(
              builder: (context, update) {
                void turn(int delta) => update(() {
                  index += delta;
                  turns++;
                });
                return Scaffold(
                  body: Column(
                    children: [
                      PagedBookView(
                        layout: layout,
                        generation: 1,
                        current: pages[index],
                        previous: index == 0 ? null : pages[index - 1],
                        next: index == 4 ? null : pages[index + 1],
                        onPrevious: () => turn(-1),
                        onNext: () => turn(1),
                        onLink: (_, _) {},
                        onNote: (_) {},
                      ),
                      PagedBookControls(
                        onPrevious: index == 0 ? null : () => turn(-1),
                        onNext: index == 4 ? null : () => turn(1),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Passage numéro 0.'), findsOneWidget);
      expect(find.bySemanticsLabel('Passage numéro 1.'), findsNothing);
      await tester.drag(find.byType(PageView), const Offset(240, 0));
      await tester.pumpAndSettle();
      expect(index, 0);
      for (var n = 0; n < 20; n++) {
        final forward = n % 8 < 4;
        if (n.isEven) {
          await tester.drag(
            find.byType(PageView),
            Offset(forward ? -240 : 240, 0),
          );
        } else {
          await tester.tap(
            find.text(forward ? 'Page suivante' : 'Page précédente'),
          );
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel('Passage numéro $index.'), findsOneWidget);
        for (final other in [
          index - 1,
          index + 1,
        ].where((n) => n >= 0 && n < 5)) {
          expect(find.bySemanticsLabel('Passage numéro $other.'), findsNothing);
        }
        expect(
          find.byType(ReaderFragmentView).evaluate().length,
          lessThanOrEqualTo(3),
        );
      }
      expect(turns, 20);
      semantics.dispose();
    });
  }
}
