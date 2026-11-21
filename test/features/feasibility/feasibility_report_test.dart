import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/features/feasibility/feasibility_report.dart';
import 'package:prototype/features/feasibility/feasibility_evaluator.dart';
import 'package:prototype/features/feasibility/measurement_collector.dart';
import 'package:prototype/features/feasibility/report_repository.dart';

void main() {
  test(
    'export excludes unexpected text and audio fields from measurements',
    () {
      final report = FeasibilityReport.empty('privacy-01');
      report.measurements.add({
        'text': 'private words',
        'audio': 'secret.wav',
        'firstPcmUs': 12,
      });
      final encoded = report.toJson().toString();
      expect(encoded, isNot(contains('private words')));
      expect(encoded, isNot(contains('secret.wav')));
      expect(encoded, contains('12'));
    },
  );
  test('missing criteria stay not evaluated and never become complete', () {
    final report = FeasibilityReport.empty('trial-01');
    expect(report.results.length, 23);
    expect(
      report.results.values.every((r) => r.status == TrialStatus.notEvaluated),
      isTrue,
    );
    expect(
      FeasibilityEvaluator.evaluate(report),
      FeasibilityVerdict.notDemonstrated,
    );
    expect(report.measurements, isEmpty);
  });
  test('complete requires physical device, local listening and every SC', () {
    final report = FeasibilityReport.empty('trial-02');
    report.physicalDevice = true;
    report.localFrenchListening = true;
    expect(FeasibilityEvaluator.evaluate(report), FeasibilityVerdict.partial);
    for (var i = 1; i <= 8; i++) {
      report.results['SC-00$i'] = TrialResult(
        TrialStatus.passed,
        evidence: ['proof.json'],
      );
    }
    expect(FeasibilityEvaluator.evaluate(report), FeasibilityVerdict.partial);
    for (final reviewer in ['a', 'b']) {
      for (var i = 1; i <= 10; i++) {
        report.addScore(reviewer, 'fr-${i.toString().padLeft(2, '0')}', 4);
      }
    }
    for (final kind in ['cold', 'warm']) {
      for (var i = 0; i < 5; i++) {
        report.measurements.add({
          'temperature': kind,
          'firstAudibleSoundUs': 1000,
        });
      }
    }
    expect(FeasibilityEvaluator.evaluate(report), FeasibilityVerdict.complete);
    report.results['SC-007'] = TrialResult(TrialStatus.notEvaluated);
    expect(FeasibilityEvaluator.evaluate(report), FeasibilityVerdict.partial);
    report.physicalDevice = false;
    expect(
      FeasibilityEvaluator.evaluate(report),
      FeasibilityVerdict.notDemonstrated,
    );
  });
  test('scores stay independent; one evaluator cannot demonstrate SC006', () {
    final report = FeasibilityReport.empty('trial-03');
    for (var i = 1; i <= 10; i++) {
      report.addScore('reviewer-a', 'fr-${i.toString().padLeft(2, '0')}', 5);
    }
    expect(report.intelligibilityDemonstrated, isFalse);
    for (var i = 1; i <= 10; i++) {
      report.addScore(
        'reviewer-b',
        'fr-${i.toString().padLeft(2, '0')}',
        i <= 8 ? 4 : 2,
      );
    }
    expect(report.intelligibilityDemonstrated, isTrue);
    expect(() => report.addScore('reviewer-a', 'fr-01', 1), throwsStateError);
    expect(FeasibilityReport.fromJson(report.toJson()).scores, report.scores);
  });
  test('monotonic measurements distinguish missing PCM and warm/cache', () {
    var tick = 100;
    final collector = MeasurementCollector(microseconds: () => tick);
    final sample = collector.begin(TrialTemperature.warm);
    tick = 5100;
    collector.markStarted(sample);
    final result = collector.finish(sample);
    expect(result['firstPcmUs'], isNull);
    expect(result['playerStartedUs'], 5000);
    expect(result['firstAudibleSoundUs'], isNull);
    expect(MeasurementCollector.median([1, 8, 3, 4, 2]), 3);
    expect(MeasurementCollector.median([]), isNull);
  });
  test(
    'private reports refuse overwrite and exports redact arbitrary strings',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ureader-reports-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = ReportRepository(directory);
      final report = FeasibilityReport.empty('trial-04');
      await repository.save(report);
      await expectLater(repository.save(report), throwsStateError);
      expect((await repository.load('trial-04')).id, report.id);
      expect(() => FeasibilityReport.empty('../escape'), throwsArgumentError);
      expect(
        () => TrialResult(TrialStatus.failed, evidence: ['/private/secret']),
        throwsArgumentError,
      );
    },
  );
}
