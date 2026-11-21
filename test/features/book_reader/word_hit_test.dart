import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/pagination.dart';
import 'package:prototype/domain/word_selection.dart';
import 'package:prototype/features/book_reader/reader_layout.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('shaped glyph hit preserves Unicode source at scale $scale', (
      tester,
    ) async {
      final block = BookBlock(
        key: ContentKey(ContentKind.book, 'glyphs', 1),
        chapterId: 'c0',
        id: 'c0-b0-s0',
        ordinal: 0,
        kind: BookBlockKind.paragraph,
        text: 'À Noël, l’amitié vingt-et-un 120 ﬂeurs café e\u0301cole.',
      );
      final key = GlobalKey();
      final layout = ReaderLayout(width: 300, height: 600, fontScale: scale);
      final measured = layout.measure(block);
      WordSelection? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ReaderFragmentView(
                layout: layout,
                fragment: PageFragment(
                  block: block,
                  startUtf16: 0,
                  endUtf16: block.text.length,
                  clipTop: 0,
                  textHeight: measured.height,
                  fullTextHeight: measured.height,
                  leading: 8,
                  trailing: 8,
                ),
                textKey: key,
                onLink: (_, _) {},
                onNote: (_) {},
                onWord: (w) => chosen = w,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final render = key.currentContext!.findRenderObject() as RenderParagraph;
      for (final word in [
        'Noël',
        'l’amitié',
        'vingt-et-un',
        '120',
        'ﬂeurs',
        'e\u0301cole',
      ]) {
        final start = block.text.indexOf(word);
        final box = render
            .getBoxesForSelection(
              TextSelection(
                baseOffset: start,
                extentOffset: start + word.length,
              ),
            )
            .first
            .toRect();
        await tester.longPressAt(render.localToGlobal(box.center));
        await tester.pumpAndSettle();
        expect(chosen?.text, word);
        expect(chosen?.start.offsetUtf16, start);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'clipped page uses full shaped context and second slice offsets',
    (tester) async {
      final key = ContentKey(ContentKind.book, 'clip', 1);
      BookBlock block(String id, int ordinal, String text) => BookBlock(
        key: key,
        chapterId: 'c0',
        id: id,
        ordinal: ordinal,
        kind: BookBlockKind.paragraph,
        text: text,
      );
      final first = block('c0-b0-s0', 0, 'Première ligne.\nUn extraor'),
          second = block('c0-b0-s1', 1, 'dinaire jardin.');
      final context = PageTextContext([first, second]),
          layout = ReaderLayout(width: 300, height: 400);
      final painter = layout.painter(first, context: context)
        ..layout(maxWidth: layout.textWidth(first));
      final top = painter.computeLineMetrics().first.height,
          height = painter.height;
      painter.dispose();
      final textKey = GlobalKey();
      WordSelection? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ReaderFragmentView(
                layout: layout,
                fragment: PageFragment(
                  block: first,
                  startUtf16: 16,
                  endUtf16: first.text.length,
                  clipTop: top,
                  textHeight: height - top,
                  fullTextHeight: height,
                  leading: 0,
                  trailing: 0,
                  context: context,
                  contextStart: 16,
                  contextEnd: context.text.length,
                ),
                textKey: textKey,
                onLink: (_, _) {},
                onNote: (_) {},
                onWord: (word) => chosen = word,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final render =
          textKey.currentContext!.findRenderObject() as RenderParagraph;
      final start = context.text.indexOf('jardin');
      final box = render
          .getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + 6),
          )
          .first
          .toRect();
      await tester.longPressAt(render.localToGlobal(box.center));
      await tester.pumpAndSettle();
      expect(chosen?.text, 'jardin');
      expect(chosen?.start.blockId, second.id);
      expect(chosen?.start.offsetUtf16, 8);
    },
  );
  test('two-slice lexical word retains both canonical locators', () {
    BookBlock block(String id, int ordinal, String text) => BookBlock(
      key: ContentKey(ContentKind.book, 'seam', 1),
      chapterId: 'c0',
      id: id,
      ordinal: ordinal,
      kind: BookBlockKind.paragraph,
      text: text,
    );
    final result = WordSelection.at([
      block('c0-b0-s0', 0, 'Un extraor'),
      block('c0-b0-s1', 1, 'dinaire jardin'),
    ], 12)!;
    expect(result.text, 'extraordinaire');
    expect(result.start.blockId, 'c0-b0-s0');
    expect(result.end.blockId, 'c0-b0-s1');
    expect(result.canStart, isFalse);
  });
}
