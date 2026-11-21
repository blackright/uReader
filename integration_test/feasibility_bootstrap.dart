import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> waitForNative(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: Text('Vérification du bilan…'))),
  );
  const bridge = MethodChannel('com.ureader.prototype/speech/v1');
  for (var attempt = 0; attempt < 50; attempt++) {
    try {
      final value = await bridge.invokeMethod<Object?>('capabilities', {
        'protocolVersion': 1,
        'command': 'capabilities',
        'requestId': 'report-probe',
        'payload': <String, Object?>{},
      });
      if (value is Map && value['protocolVersion'] == 1) return;
    } on MissingPluginException {
      /* Wait for activity attachment, never fake a result. */
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  fail('Pont natif non attaché');
}
