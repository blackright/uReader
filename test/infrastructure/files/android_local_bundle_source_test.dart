import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/infrastructure/files/android_local_bundle_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.ureader.prototype/local_bundle/v1');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('no implicit selection and bounded streamed file reads', () async {
    final calls = <String>[];
    var read = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'chooseFolder' => true,
            'read' => Uint8List.fromList(read++ == 0 ? [1, 2, 3] : []),
            _ => null,
          };
        });
    final source = AndroidLocalBundleSource();
    expect(calls, isEmpty);
    expect(await source.chooseFolder(), isTrue);
    expect(await source.readFile('tokenizer.json').expand((c) => c).toList(), [
      1,
      2,
      3,
    ]);
    await source.close();
    expect(calls, ['chooseFolder', 'open', 'read', 'read', 'close']);
  });
  test('late folder result after cancellation is refused', () async {
    final selected = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async =>
              call.method == 'chooseFolder' ? await selected.future : null,
        );
    final source = AndroidLocalBundleSource();
    final choosing = source.chooseFolder();
    await Future<void>.delayed(Duration.zero);
    await source.close();
    selected.complete(true);
    expect(await choosing, isFalse);
  });
  test('oversized platform chunks never reach staging', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'read'
              ? Uint8List(65537)
              : call.method == 'chooseFolder'
              ? true
              : null,
        );
    final source = AndroidLocalBundleSource();
    await source.chooseFolder();
    await expectLater(
      source.readFile('tokenizer.json').drain<void>(),
      throwsA(
        isA<AppError>().having(
          (e) => e.code,
          'code',
          ErrorCode.storageLimitExceeded,
        ),
      ),
    );
    await source.close();
  });
}
