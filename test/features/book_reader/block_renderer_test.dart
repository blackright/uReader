import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/book_reader/book_block_renderer.dart';

void main() {
  testWidgets(
    'ordered safe inline text, note and distinct link action remain accessible at large scale',
    (tester) async {
      final key = ContentKey(ContentKind.book, 'book', 1);
      var clicks = 0;
      final block = BookBlock(
        key: key,
        chapterId: 'c0',
        id: 'b0',
        ordinal: 0,
        kind: BookBlockKind.tableCell,
        text: 'Bonjour lien',
        inline: [
          BookInline(startUtf16: 0, endUtf16: 7, strong: true),
          BookInline(
            startUtf16: 8,
            endUtf16: 12,
            link: BookLink('#note', 8, 12),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3.2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: BookBlockRenderer(
                  block: block,
                  onLink: (_, _) => clicks++,
                  onNote: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Bonjour lien'), findsOneWidget);
      expect(find.text('Ouvrir le lien : lien'), findsOneWidget);
      await tester.ensureVisible(find.text('Ouvrir le lien : lien'));
      await tester.tap(find.text('Ouvrir le lien : lien'));
      expect(clicks, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'identified note is separate and an image keeps its alternative',
    (tester) async {
      final key = ContentKey(ContentKind.book, 'book', 1);
      final note = BookBlock(
        key: key,
        chapterId: 'c0',
        id: 'n',
        ordinal: 0,
        kind: BookBlockKind.paragraph,
        text: 'Contenu note',
        speechEligible: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookBlockRenderer(
              block: note,
              onLink: (_, _) {},
              onNote: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('Consulter la note'), findsOneWidget);
      expect(find.text('Contenu note'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookBlockRenderer(
              block: BookBlock(
                key: key,
                chapterId: 'c0',
                id: 'img',
                ordinal: 0,
                kind: BookBlockKind.image,
                text: '',
                speechEligible: false,
                alternative: 'Un jardin',
              ),
              onLink: (_, _) {},
              onNote: (_) {},
            ),
          ),
        ),
      );
      expect(find.textContaining('Un jardin'), findsOneWidget);
    },
  );
}
