import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/app/dependencies.dart';
import 'package:prototype/features/feasibility/feasibility_screen.dart';

import 'feasibility_bootstrap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real report screen remains usable without loading speech', (
    tester,
  ) async {
    await waitForNative(tester);
    final deps = await AppDependencies.open();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FeasibilityScreen(repository: deps.reports)),
      ),
    );
    await tester.pumpAndSettle();
    for (
      var attempt = 0;
      attempt < 50 && find.text('Bilan de faisabilité').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.scrollUntilVisible(find.text('Exporter le bilan'), 200);
    await tester.tap(find.text('Exporter le bilan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('Export annulé.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await deps.dispose();
  });
}
