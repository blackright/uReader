import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/features/feasibility/feasibility_report.dart';
import 'package:prototype/features/feasibility/feasibility_screen.dart';
import 'package:prototype/features/feasibility/report_repository.dart';

class WidgetReportRepository extends ReportRepository {
  WidgetReportRepository() : super(Directory('.'));
  @override
  Future<void> save(FeasibilityReport report) async {}
}

void main() {
  for (final scale in [1.0, 2.0, 3.2]) {
    testWidgets('negative report, cancel and export error at scale $scale', (
      tester,
    ) async {
      var exports = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.ureader.prototype/reports/v1'),
            (call) async {
              exports++;
              throw PlatformException(code: 'export_failed');
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('com.ureader.prototype/reports/v1'),
              null,
            ),
      );
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: FeasibilityScreen(
                repository: WidgetReportRepository(),
                loadReport: () async => FeasibilityReport.empty('negative-01'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Faisabilité non démontrée'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Exporter le bilan'), 200);
      await tester.tap(find.text('Exporter le bilan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(exports, 0);
      expect(find.text('Export annulé.'), findsOneWidget);
      await tester.tap(find.text('Exporter le bilan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(exports, 1);
      expect(find.text('Export impossible. Réessayez.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
