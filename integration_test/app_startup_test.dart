import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Le squelette Android démarre sans charger de modèle', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.text('uReader — Prototype'), findsOneWidget);
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (find.byType(NavigationBar).evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.text('Voix'));
    await tester.pumpAndSettle();
    expect(find.text('Préparation de la voix'), findsOneWidget);
    await tester.tap(find.text('Bilan'));
    await tester.pumpAndSettle();
    expect(find.text('Bilan de faisabilité'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
