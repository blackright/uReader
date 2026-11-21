import 'feasibility_report.dart';

class FeasibilityEvaluator {
  static FeasibilityVerdict evaluate(FeasibilityReport report) {
    if (!report.physicalDevice || !report.localFrenchListening) {
      return FeasibilityVerdict.notDemonstrated;
    }
    final all = List.generate(
      8,
      (i) => 'SC-${(i + 1).toString().padLeft(3, '0')}',
    ).every((id) => report.results[id]?.status == TrialStatus.passed);
    final repeated = ['cold', 'warm'].every(
      (kind) =>
          report.measurements
              .where(
                (m) =>
                    m['temperature'] == kind && m['firstAudibleSoundUs'] is num,
              )
              .length >=
          5,
    );
    return all && report.intelligibilityDemonstrated && repeated
        ? FeasibilityVerdict.complete
        : FeasibilityVerdict.partial;
  }

  static String label(FeasibilityVerdict value) => switch (value) {
    FeasibilityVerdict.complete =>
      'Faisabilité démontrée sur les configurations évaluées',
    FeasibilityVerdict.partial => 'Faisabilité partielle',
    FeasibilityVerdict.notDemonstrated => 'Faisabilité non démontrée',
  };
}
