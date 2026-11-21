import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/features/book_reader/word_highlight_overlay.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('highlight preserves wrapping and semantic text in $brightness', (
      tester,
    ) async {
      final key = GlobalKey();
      const text =
          'Bonjour le jardin. Voici une longue phrase pour vérifier les retours à la ligne.';
      Widget surface(bool highlight) => MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 140,
              child: WordHighlightOverlay(
                paragraphKey: key,
                words: highlight ? [const TextRange(start: 8, end: 10)] : [],
                paragraphs: highlight
                    ? [const TextRange(start: 0, end: text.length)]
                    : [],
                child: RichText(
                  key: key,
                  text: const TextSpan(
                    text: text,
                    style: TextStyle(fontSize: 18),
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(surface(false));
      final before =
          (key.currentContext!.findRenderObject() as RenderParagraph).size;
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(surface(true));
        await tester.pump();
        final paragraph =
            key.currentContext!.findRenderObject() as RenderParagraph;
        expect(paragraph.size, before);
        expect(
          paragraph.getBoxesForSelection(
            const TextSelection(baseOffset: 8, extentOffset: 10),
          ),
          isNotEmpty,
        );
        expect(find.bySemanticsLabel(text), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}
