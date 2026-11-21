import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/infrastructure/speech/speech_messages.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Le vrai pont Android répond sans activer le bundle expérimental',
    (tester) async {
      const channel = MethodChannel(SpeechMessage.commandChannel);
      Future<Object?> send(SpeechMessage message) =>
          channel.invokeMethod<Object?>(message.command.name, message.toWire());

      final capabilities = await send(
        SpeechMessage(command: SpeechCommand.capabilities, requestId: 'caps-1'),
      ) as Map;
      expect(capabilities['protocolVersion'], 1);
      expect(capabilities['languages'], isEmpty);
      expect(capabilities['voices'], isEmpty);

      await expectLater(
        channel.invokeMethod<Object?>('capabilities', {
          ...SpeechMessage(
            command: SpeechCommand.capabilities,
            requestId: 'invalid-version',
          ).toWire(),
          'protocolVersion': 2,
        }),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'invalidMessage',
          ),
        ),
      );
      await expectLater(
        send(
          SpeechMessage(
            command: SpeechCommand.loadBundle,
            requestId: 'load-1',
            payload: {
              'bundleId': 'g0-candidate',
              'version': 'audit-1',
              'manifestDigest': 'a' * 64,
            },
          ),
        ),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'modelMissing',
          ),
        ),
      );
      for (var i = 0; i < 2; i++) {
        await send(
          SpeechMessage(
            command: SpeechCommand.cancel,
            requestId: 'cancel-$i',
            token: SessionToken('bridge-session', 1),
          ),
        );
      }
      for (var i = 0; i < 2; i++) {
        await send(
          SpeechMessage(
            command: SpeechCommand.dispose,
            requestId: 'dispose-$i',
          ),
        );
      }
    },
  );
}
