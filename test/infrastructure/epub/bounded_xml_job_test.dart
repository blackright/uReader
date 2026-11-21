import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/epub/bounded_xml_job.dart';

Future<String> waitingWorker(String source) async {
  await Future<void>.delayed(const Duration(hours: 1));
  return source;
}

Future<String> echo(String source) async => source;
void main() {
  test('worker returns only its typed result', () async {
    expect(await BoundedXmlJob.run('value', echo), 'value');
  });
  test('hung metadata worker is killed after cancellation grace', () async {
    var cancelled = false;
    final clock = Stopwatch()..start();
    final result = BoundedXmlJob.run(
      'private value',
      waitingWorker,
      cancelled: () => cancelled,
    );
    final check = expectLater(
      result,
      throwsA(
        isA<BookFailure>().having((e) => e.code, 'code', BookError.cancelled),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    cancelled = true;
    await check;
    expect(clock.elapsedMilliseconds, lessThan(5000));
  });
}
