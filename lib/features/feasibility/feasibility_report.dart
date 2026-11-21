import 'feasibility_evaluator.dart';

enum TrialStatus { passed, failed, notEvaluated }

enum FeasibilityVerdict { complete, partial, notDemonstrated }

void safeId(String value) {
  if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,95}$').hasMatch(value)) {
    throw ArgumentError('Identifiant invalide');
  }
}

class TrialResult {
  TrialResult(
    this.status, {
    List<String> evidence = const [],
    this.reason = 'not_measured',
    this.nextAction = 'evaluate',
  }) : evidence = List.unmodifiable(evidence) {
    safeId(reason);
    safeId(nextAction);
    for (final path in evidence) {
      if (!RegExp(r'^[a-zA-Z0-9_./-]+$').hasMatch(path) ||
          path.startsWith('/') ||
          path.contains('..')) {
        throw ArgumentError('Preuve relative requise');
      }
    }
    if (status == TrialStatus.passed && evidence.isEmpty) {
      throw ArgumentError('Preuve requise');
    }
  }
  final TrialStatus status;
  final List<String> evidence;
  final String reason;
  final String nextAction;
  Map<String, Object?> toJson() => {
    'status': status == TrialStatus.notEvaluated
        ? 'not_evaluated'
        : status.name,
    'evidence': evidence,
    'reason': reason,
    'nextAction': nextAction,
  };
  factory TrialResult.fromJson(Map<String, dynamic> json) => TrialResult(
    json['status'] == 'not_evaluated'
        ? TrialStatus.notEvaluated
        : TrialStatus.values.byName(json['status'] as String),
    evidence: (json['evidence'] as List).cast<String>(),
    reason: json['reason'] as String,
    nextAction: json['nextAction'] as String,
  );
}

/// Only curated metadata is exported; no corpus text, audio, serial, path or logs.
class Configuration {
  Configuration({
    this.model,
    this.androidApi,
    this.abi,
    this.ramKiB,
    this.pageSize,
    this.buildMode = 'unknown',
    this.bundleDigest,
    this.fontScale,
    this.talkBack,
  });
  final String? model, abi, bundleDigest;
  final int? androidApi, ramKiB, pageSize;
  final String buildMode;
  final double? fontScale;
  final bool? talkBack;
  Map<String, Object?> toJson() => {
    'model': model,
    'androidApi': androidApi,
    'abi': abi,
    'ramKiB': ramKiB,
    'pageSize': pageSize,
    'buildMode': buildMode,
    'bundleDigest': bundleDigest,
    'fontScale': fontScale,
    'talkBack': talkBack,
  };
  factory Configuration.fromJson(Map<String, dynamic> j) => Configuration(
    model: j['model'] as String?,
    androidApi: j['androidApi'] as int?,
    abi: j['abi'] as String?,
    ramKiB: j['ramKiB'] as int?,
    pageSize: j['pageSize'] as int?,
    buildMode: j['buildMode'] as String,
    bundleDigest: j['bundleDigest'] as String?,
    fontScale: (j['fontScale'] as num?)?.toDouble(),
    talkBack: j['talkBack'] as bool?,
  );
}

class FeasibilityReport {
  FeasibilityReport.empty(this.id) : createdAt = DateTime.now().toUtc() {
    safeId(id);
  }
  final String id;
  DateTime createdAt;
  bool finalReport = false;
  bool physicalDevice = false;
  bool localFrenchListening = false;
  Configuration configuration = Configuration();
  final Map<String, TrialResult> results = {
    for (var i = 1; i <= 15; i++)
      'FR-${i.toString().padLeft(3, '0')}': TrialResult(
        TrialStatus.notEvaluated,
      ),
    for (var i = 1; i <= 8; i++)
      'SC-${i.toString().padLeft(3, '0')}': TrialResult(
        TrialStatus.notEvaluated,
      ),
  };
  final List<Map<String, Object?>> measurements = [];
  final Map<String, String?> provenance = {};
  final Map<String, Map<String, int>> scores = {};
  void addScore(String evaluator, String text, int score) {
    safeId(evaluator);
    if (!RegExp(r'^fr-(0[1-9]|10)$').hasMatch(text) || score < 1 || score > 5) {
      throw ArgumentError('Note invalide');
    }
    final row = scores.putIfAbsent(evaluator, () => {});
    if (row.containsKey(text)) {
      throw StateError('Note indépendante déjà consignée');
    }
    row[text] = score;
  }

  bool get intelligibilityDemonstrated =>
      scores.length >= 2 &&
      scores.values
              .where(
                (row) =>
                    row.length == 10 &&
                    row.values.where((score) => score >= 4).length >= 8,
              )
              .length >=
          2;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'finalReport': finalReport,
    'physicalDevice': physicalDevice,
    'localFrenchListening': localFrenchListening,
    'configuration': configuration.toJson(),
    'provenance': {
      for (final key in [
        'commit',
        'flutter',
        'dart',
        'java',
        'gradle',
        'kotlin',
        'runtime',
        'weightsRevision',
        'voiceRevision',
        'exportRecipe',
        'tokenizerDigest',
        'corpusDigest',
        'network',
        'power',
        'thermal',
        'batteryStart',
        'batteryEnd',
        'duration',
        'licenseEvidence',
        'protocolEvidence',
      ])
        key: provenance[key],
    },
    'results': {for (final e in results.entries) e.key: e.value.toJson()},
    'conclusion': FeasibilityEvaluator.label(
      FeasibilityEvaluator.evaluate(this),
    ),
    'measurements': measurements
        .map(
          (m) => {
            for (final key in [
              'elapsedUs',
              'firstPcmUs',
              'playerStartedUs',
              'firstAudibleSoundUs',
              'memoryBeforeKiB',
              'memoryPeakKiB',
              'memoryAfterKiB',
              'batteryDeltaPercent',
              'storageBytes',
            ])
              key: m[key] is num ? m[key] : null,
            'temperature':
                ['cold', 'warm', 'cacheHit'].contains(m['temperature'])
                ? m['temperature']
                : 'unknown',
          },
        )
        .toList(),
    'scores': scores,
  };
  factory FeasibilityReport.fromJson(Map<String, dynamic> j) {
    if (j['schemaVersion'] != 1) {
      throw const FormatException('Version inconnue');
    }
    final r = FeasibilityReport.empty(j['id'] as String);
    r.createdAt = DateTime.parse(j['createdAt'] as String);
    r.finalReport = j['finalReport'] as bool;
    r.physicalDevice = j['physicalDevice'] as bool;
    r.localFrenchListening = j['localFrenchListening'] as bool;
    r.configuration = Configuration.fromJson(
      j['configuration'] as Map<String, dynamic>,
    );
    if (j['provenance'] is Map) {
      r.provenance.addAll(
        (j['provenance'] as Map).map(
          (k, v) => MapEntry(k as String, v as String?),
        ),
      );
    }
    for (final e in (j['results'] as Map<String, dynamic>).entries) {
      if (!r.results.containsKey(e.key)) {
        throw const FormatException('Critère inconnu');
      }
      r.results[e.key] = TrialResult.fromJson(e.value as Map<String, dynamic>);
    }
    for (final e in (j['scores'] as Map<String, dynamic>).entries) {
      for (final s in (e.value as Map<String, dynamic>).entries) {
        r.addScore(e.key, s.key, s.value as int);
      }
    }
    r.measurements.addAll(
      (j['measurements'] as List).map(
        (m) => Map<String, Object?>.from(m as Map),
      ),
    );
    return r;
  }
}
