// Computational corpus check only. Never plays audio or closes G1.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'alignment_laboratory.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'all corpus occurrences decode with canonical coordinates, without playback',
    (tester) async {
      runApp(
        const MaterialApp(
          home: AlignmentLaboratory(corpusRun: 'corpus-20261120-01'),
        ),
      );
      for (var index = 0; index < 120; index++) {
        for (
          var wait = 0;
          wait < 300 &&
              find.text('Jouer l’extrait expérimental').evaluate().isEmpty;
          wait++
        ) {
          await tester.pump(const Duration(milliseconds: 30));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        final status = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .where((s) => s.startsWith('Banc indisponible'))
            .join(' ; ');
        expect(
          find.text('Jouer l’extrait expérimental'),
          findsOneWidget,
          reason: status,
        );
        expect(find.text('Segment ${index + 1} / 120'), findsOneWidget);
        expect(find.textContaining('Position player : 0 ms'), findsOneWidget);
        if (index < 119) {
          final next = find.text('Segment suivant');
          await tester.ensureVisible(next);
          await tester.pumpAndSettle();
          await tester.tap(next);
          await tester.pump();
        }
      }
      final export = find.text('Exporter les cues sans son');
      await tester.ensureVisible(export);
      await tester.pumpAndSettle();
      await tester.tap(export);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
