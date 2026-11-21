import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/infrastructure/diagnostics/safe_diagnostics.dart';

void main() {
  test('Ne sérialise que codes et durées autorisés', () {
    final records = <Map<String, Object>>[];
    final clock = SystemClock();
    final diagnostics = SafeDiagnostics(clock: clock, sink: records.add);
    diagnostics.record(
      DiagnosticEvent.recoveryFailed,
      error: ErrorCode.storageUnavailable,
    );
    expect(
      records.single.keys,
      unorderedEquals(['event', 'elapsedMicros', 'error']),
    );
    expect(records.single['error'], 'storageUnavailable');
    expect(clock.elapsed.inMicroseconds, greaterThanOrEqualTo(0));
    for (final code in ErrorCode.values) {
      expect(AppError(code).message, isNotEmpty);
      expect(AppError(code).toString(), isNot(contains('Exception:')));
    }
  });
}
