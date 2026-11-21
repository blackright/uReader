import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/app/dependencies.dart';
import 'package:prototype/features/feasibility/feasibility_report.dart';
import 'package:prototype/features/feasibility/feasibility_evaluator.dart';

import 'feasibility_bootstrap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('interim report survives private persistence, remains partial', (
    tester,
  ) async {
    await waitForNative(tester);
    final deps = await AppDependencies.open();
    try {
      final report = FeasibilityReport.fromJson(
        jsonDecode(await rootBundle.loadString('assets/reports/interim.json'))
            as Map<String, dynamic>,
      );
      final copy = FeasibilityReport.fromJson(
        report.toJson()
          ..['id'] = 'physical-${DateTime.now().microsecondsSinceEpoch}',
      );
      await deps.reports.save(copy);
      final loaded = await deps.reports.load(copy.id);
      expect(loaded.results.length, 23);
      expect(FeasibilityEvaluator.evaluate(loaded), FeasibilityVerdict.partial);
      await expectLater(deps.reports.save(copy), throwsStateError);
    } finally {
      await deps.dispose();
    }
  });
}
