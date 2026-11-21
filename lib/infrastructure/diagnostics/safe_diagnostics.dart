import '../../domain/app_error.dart';

abstract interface class AppClock {
  DateTime get now;
  Duration get elapsed;
}

class SystemClock implements AppClock {
  SystemClock() : _stopwatch = Stopwatch()..start();
  final Stopwatch _stopwatch;
  @override
  DateTime get now => DateTime.now().toUtc();
  @override
  Duration get elapsed => _stopwatch.elapsed;
}

enum DiagnosticEvent { recoveryFailed, recoveryCompleted, storageUnavailable }

/// L'API n'accepte ni texte libre, ni exception brute, ni chemin.
class SafeDiagnostics {
  SafeDiagnostics({required this.clock, this.sink});
  final AppClock clock;
  final void Function(Map<String, Object>)? sink;
  void record(DiagnosticEvent event, {ErrorCode? error}) {
    sink?.call(
      Map.unmodifiable({
        'event': event.name,
        'elapsedMicros': clock.elapsed.inMicroseconds,
        if (error != null) 'error': error.name,
      }),
    );
  }
}
