import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/infrastructure/speech/speech_messages.dart';

import '../../fakes/fake_speech_engine.dart';

void main() {
  test('Contrat versionné, payload borné et jeton obligatoire', () {
    final message = SpeechMessage(
      command: SpeechCommand.capabilities,
      requestId: 'r1',
    );
    expect(
      SpeechMessage.fromWire(message.toWire()).command,
      SpeechCommand.capabilities,
    );
    for (final wire in [
      {...message.toWire(), 'protocolVersion': 2},
      {...message.toWire(), 'command': 'unknown'},
      {
        ...message.toWire(),
        'payload': {'url': 'https://untrusted.example/model'},
      },
      {...message.toWire(), 'generation': 1},
    ]) {
      expect(() => SpeechMessage.fromWire(wire), throwsA(isA<AppError>()));
    }
    expect(
      () => SpeechMessage(command: SpeechCommand.cancel, requestId: 'r1'),
      throwsA(isA<AppError>()),
    );
  });
  test(
    'Faux moteur : annulation et disposal idempotents, retour tardif explicite',
    () async {
      final fake = FakeSpeechEngine();
      final events = <SpeechEvent>[];
      final subscription = fake.events.listen(events.add);
      expect((await fake.capabilities()).languages, isEmpty);
      await fake.loadBundle(
        BundleDescriptor(
          id: 'test',
          version: 'v1',
          manifestDigest: 'a' * 64,
          files: [
            BundleFile(
              relativePath: 'model.bin',
              byteSize: 0,
              sha256: 'b' * 64,
            ),
          ],
        ),
      );
      final token = SessionToken('session1', 1);
      await fake.synthesize(
        SpeechRequest(
          requestId: 'request1',
          token: token,
          start: Locator(
            textId: 'text1',
            corpusVersion: 1,
            passageId: 'p1',
            offsetUtf16: 0,
          ),
          end: Locator(
            textId: 'text1',
            corpusVersion: 1,
            passageId: 'p1',
            offsetUtf16: 7,
          ),
          text: 'Bonjour',
          voiceId: 'fake-voice',
          bundleId: 'test',
        ),
      );
      await fake.cancel(token);
      await fake.cancel(token);
      fake.complete('request1');
      expect(events.single.kind, SpeechEventKind.cancelled);
      fake.complete('request1', simulateLateResult: true);
      expect(events.last.token.generation, 1);
      expect(events.last.kind, SpeechEventKind.completed);
      await fake.dispose();
      await fake.dispose();
      await subscription.cancel();
    },
  );
  test('L’adaptateur par défaut n’annonce aucune voix', () async {
    final engine = UnavailableSpeechEngine();
    expect((await engine.capabilities()).voices, isEmpty);
    await engine.dispose();
  });

  test('Sortie complète typée et message immuable', () {
    final token = SessionToken('session1', 1);
    expect(
      () => SpeechEvent(
        requestId: 'r1',
        token: token,
        kind: SpeechEventKind.completed,
      ),
      throwsA(isA<AppError>()),
    );
    expect(
      () => SpeechEvent(
        requestId: 'r1',
        token: token,
        kind: SpeechEventKind.failed,
      ),
      throwsA(isA<AppError>()),
    );
    final start = <String, Object?>{
      'textId': 'demo',
      'corpusVersion': 1,
      'passageId': 'p1',
      'offsetUtf16': 0,
    };
    final message = SpeechMessage(
      command: SpeechCommand.synthesize,
      requestId: 'r1',
      token: token,
      payload: {
        'text': 'A',
        'voiceId': 'voice',
        'bundleId': 'test',
        'start': start,
        'end': {...start, 'offsetUtf16': 1},
      },
    );
    start['textId'] = 'changed';
    expect((message.payload['start']! as Map)['textId'], 'demo');
    expect(
      SpeechMessage.fromWire(message.toWire()).token!.matches(token),
      isTrue,
    );
  });
}
