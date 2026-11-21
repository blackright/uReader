enum TrialTemperature { cold, warm, cacheHit }

class MeasurementSample {
  MeasurementSample(this.temperature, this.start);
  final TrialTemperature temperature;
  final int start;
  int? pcm, playerStarted;
}

class MeasurementCollector {
  MeasurementCollector({int Function()? microseconds}) {
    final watch = Stopwatch()..start();
    _microseconds = microseconds ?? () => watch.elapsedMicroseconds;
  }
  late final int Function() _microseconds;
  MeasurementSample begin(TrialTemperature temperature) =>
      MeasurementSample(temperature, _microseconds());
  void markPcm(MeasurementSample sample) =>
      sample.pcm ??= _microseconds() - sample.start;
  void markStarted(MeasurementSample sample) =>
      sample.playerStarted ??= _microseconds() - sample.start;
  Map<String, Object?> finish(MeasurementSample sample) => {
    'temperature': sample.temperature.name,
    'elapsedUs': _microseconds() - sample.start,
    'firstPcmUs': sample.pcm,
    'playerStartedUs': sample.playerStarted,
    'firstAudibleSoundUs': null,
    'memoryBeforeKiB': null,
    'memoryPeakKiB': null,
    'memoryAfterKiB': null,
    'batteryDeltaPercent': null,
    'storageBytes': null,
    'availability': 'partial_events_only',
  };
  static double? median(List<num> values) {
    if (values.isEmpty) return null;
    final sorted = values.toList()..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle].toDouble()
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
