import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/features/demo_reader/demo_reader_screen.dart';
import 'package:prototype/features/demo_reader/corpus_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Sans voix : sélectionner et consulter les dix textes', (
    tester,
  ) async {
    // Explicitly omit the audio coordinator: this remains the no-voice contract
    // even when the normal application can use the privately provisioned bundle.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DemoReaderScreen(corpus: CorpusRepository())),
      ),
    );
    for (
      var i = 0;
      i < 150 && find.text('Choisir un texte').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('Écoute indisponible'), findsOneWidget);
    const titles = <String>[
      'Le jardin du matin',
      'Le dernier tramway',
      'Une lettre retrouvée',
      'Accents et apostrophes',
      'Nombres au marché',
      'Abréviations et ponctuation',
      'Préparer une randonnée',
      'La bibliothèque du quartier',
      'Réparer un vélo',
      'Une longue promenade au bord du canal',
    ];
    for (final title in titles) {
      final choice = find.widgetWithText(OutlinedButton, title).hitTestable();
      await tester.scrollUntilVisible(
        choice,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsWidgets);
      expect(find.textContaining('Écoute indisponible'), findsOneWidget);
      await tester.tap(find.text('Tous les textes'));
      await tester.pumpAndSettle();
    }
  });
}
