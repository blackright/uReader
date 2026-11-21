// Preparation smoke only; not an audiovisual acceptance or G1 score.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'alignment_laboratory.dart' as lab;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('isolated alignment lab requires an explicit playback action', (
    tester,
  ) async {
    lab.main();
    for (
      var i = 0;
      i < 200 && find.text('Jouer l’extrait expérimental').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    final status = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .where(
          (s) =>
              s.startsWith('Banc indisponible') || s.startsWith('Chargement'),
        )
        .join(' ; ');
    expect(
      find.text('Jouer l’extrait expérimental'),
      findsOneWidget,
      reason: status,
    );
    expect(find.textContaining('Position player : 0 ms'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
