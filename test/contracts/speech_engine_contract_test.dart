import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/infrastructure/speech/speech_messages.dart';

import '../fakes/fake_speech_engine.dart';

void main() {
  test('Le transport conserve session, génération et plage UTF-16', () {
    final message = SpeechMessage(
      command: SpeechCommand.synthesize,
      requestId: 'r1',
      token: SessionToken('s1', 4),
      payload: {
        'text': 'Été 🌱',
        'voiceId': 'test-voice',
        'bundleId': 'test',
        'start': {
          'textId': 't1',
          'corpusVersion': 1,
          'passageId': 'p1',
          'offsetUtf16': 0,
        },
        'end': {
          'textId': 't1',
          'corpusVersion': 1,
          'passageId': 'p1',
          'offsetUtf16': 6,
        },
      },
    );
    final decoded = SpeechMessage.fromWire(message.toWire());
    expect(decoded.token!.matches(SessionToken('s1', 4)), isTrue);
    expect(decoded.token!.matches(SessionToken('s1', 5)), isFalse);
    expect(decoded.payload['text'], 'Été 🌱');
    expect(
      () => SpeechMessage.fromWire({...message.toWire(), 'generation': -1}),
      throwsA(isA<AppError>()),
    );
    expect(
      () => SpeechMessage.fromWire({...message.toWire(), 'protocolVersion': 2}),
      throwsA(isA<AppError>()),
    );
  });
  test(
    'Annulation répétée et retour tardif conservent le jeton original',
    () async {
      final engine = FakeSpeechEngine();
      final events = <SpeechEvent>[];
      final subscription = engine.events.listen(events.add);
      await engine.loadBundle(
        BundleDescriptor(
          id: 'test',
          version: 'v1',
          manifestDigest: 'a' * 64,
          files: [
            BundleFile(relativePath: 'test.bin', byteSize: 0, sha256: 'b' * 64),
          ],
        ),
      );
      final old = SessionToken('session', 1);
      await engine.synthesize(
        SpeechRequest(
          requestId: 'r1',
          token: old,
          start: Locator(
            textId: 't1',
            corpusVersion: 1,
            passageId: 'p1',
            offsetUtf16: 0,
          ),
          end: Locator(
            textId: 't1',
            corpusVersion: 1,
            passageId: 'p1',
            offsetUtf16: 7,
          ),
          text: 'Bonjour',
          voiceId: 'fake-voice',
          bundleId: 'test',
        ),
      );
      await engine.cancel(old);
      await engine.cancel(old);
      expect(events.single.kind, SpeechEventKind.cancelled);
      engine.complete('r1', simulateLateResult: true);
      expect(events.last.token.matches(SessionToken('session', 2)), isFalse);
      // La simulation prouve le transport ; le rejet par le lecteur attend T021/G0.
      await engine.dispose();
      await engine.dispose();
      await engine.cancel(old);
      await subscription.cancel();
    },
  );
}
