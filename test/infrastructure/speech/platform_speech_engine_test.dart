import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/infrastructure/files/audio_cache.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';
import 'package:prototype/infrastructure/speech/platform_speech_engine.dart';

Uint8List wavFixture() {
  final bytes = Uint8List(92);
  final data = ByteData.sublistView(bytes);
  for (final e in {0: 'RIFF', 8: 'WAVE', 12: 'fmt ', 36: 'data'}.entries) {
    bytes.setRange(e.key, e.key + 4, ascii.encode(e.value));
  }
  for (final e in {4: 84, 16: 16, 24: 24000, 28: 48000, 40: 48}.entries) {
    data.setUint32(e.key, e.value, Endian.little);
  }
  for (final e in {20: 1, 22: 1, 32: 2, 34: 16}.entries) {
    data.setUint16(e.key, e.value, Endian.little);
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AudioCache cache;
  late PlatformSpeechEngine engine;
  late StreamController<dynamic> events;
  final releases = <String>[];
  const command = MethodChannel('test-speech');
  const audio = MethodChannel('test-audio');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Locator locator(int offset) => Locator(
    textId: 't',
    corpusVersion: 1,
    passageId: 'p',
    offsetUtf16: offset,
  );
  SpeechRequest request() => SpeechRequest(
    requestId: 'r1',
    token: SessionToken('s', 1),
    start: locator(0),
    end: locator(5),
    text: 'Salut',
    voiceId: 'estelle',
    bundleId: 'bundle',
  );
  Map<String, Object?> completed() => {
    'protocolVersion': 1,
    'requestId': 'r1',
    'sessionId': 's',
    'generation': 1,
    'kind': 'completed',
    'output': {
      'audioHandle': 'native-handle',
      'sampleRate': 24000,
      'channels': 1,
      'encoding': 'pcm16',
      'durationMs': 1,
      'byteSize': 92,
      'start': {
        'textId': 't',
        'corpusVersion': 1,
        'passageId': 'p',
        'offsetUtf16': 0,
      },
      'end': {
        'textId': 't',
        'corpusVersion': 1,
        'passageId': 'p',
        'offsetUtf16': 5,
      },
    },
  };
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ureader-platform-');
    cache = AudioCache(await PrivateFileStore.open(root));
    events = StreamController<dynamic>();
    releases.clear();
    messenger.setMockMethodCallHandler(command, (_) async => null);
    messenger.setMockMethodCallHandler(audio, (call) async {
      if (call.method == 'readAudio') return wavFixture();
      if (call.method == 'releaseAudio') {
        releases.add((call.arguments as Map)['audioHandle'] as String);
      }
      return null;
    });
    engine = PlatformSpeechEngine(
      cache,
      commands: command,
      audio: audio,
      nativeEvents: events.stream,
    );
    await engine.loadBundle(
      BundleDescriptor(
        id: 'bundle',
        version: 'v1',
        manifestDigest: 'a' * 64,
        files: [
          BundleFile(relativePath: 'test', byteSize: 1, sha256: 'b' * 64),
        ],
      ),
    );
  });
  tearDown(() async {
    await engine.dispose();
    await events.close();
    messenger.setMockMethodCallHandler(command, null);
    messenger.setMockMethodCallHandler(audio, null);
    await root.delete(recursive: true);
  });
  test('WAV validé et publié, handle natif libéré, cache verrouillé pendant lecture', () async {
    final result = engine.events.first;
    await engine.synthesize(request());
    events.add(completed());
    final event = await result;
    expect(event.kind, SpeechEventKind.completed);
    final key = event.audioHandle!;
    expect(await (await cache.files.audioCacheFile(key)).length(), 92);
    await Future<void>.delayed(Duration.zero);
    expect(releases, ['native-handle']);
    final lease = await cache.files.acquire('cache/audio/$key.wav');
    await expectLater(cache.remove(key), throwsA(anything));
    lease.release();
    await cache.remove(key);
    expect(
      root.listSync(recursive: true).where((e) => e.path.endsWith('.part')),
      isEmpty,
    );
  });
  test('WAV tronqué rejeté et handle libéré', () async {
    messenger.setMockMethodCallHandler(audio, (call) async {
      if (call.method == 'readAudio') return Uint8List(44);
      if (call.method == 'releaseAudio') releases.add('released');
      return null;
    });
    final result = engine.events.first;
    await engine.synthesize(request());
    events.add(completed());
    expect((await result).kind, SpeechEventKind.failed);
    await Future<void>.delayed(Duration.zero);
    expect(releases, ['released']);
  });
  test(
    'Annulation pendant le transfert interdit toute publication tardive',
    () async {
      final reading = Completer<void>();
      final bytes = Completer<Uint8List>();
      messenger.setMockMethodCallHandler(audio, (call) async {
        if (call.method == 'readAudio') {
          reading.complete();
          return bytes.future;
        }
        if (call.method == 'releaseAudio') releases.add('released');
        return null;
      });
      final received = <SpeechEvent>[];
      final sub = engine.events.listen(received.add);
      await engine.synthesize(request());
      events.add(completed());
      await reading.future;
      final cancelled = engine.cancel(request().token);
      bytes.complete(wavFixture());
      await cancelled;
      expect(
        received.where((e) => e.kind == SpeechEventKind.completed),
        isEmpty,
      );
      expect(releases, ['released']);
      await engine.cancel(request().token);
      await sub.cancel();
    },
  );
  test('Clé versionnée et absence de contenu dans le nom de cache', () {
    String key(String version) => AudioCache.key(
      bundleDigest: 'a' * 64,
      voice: 'estelle',
      text: 'Texte privé',
      normalizerVersion: version,
    );
    expect(key('v1'), matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(key('v1'), isNot(key('v2')));
  });
  test(
    'Texte normalisé distinct, repères conservés sur le texte source',
    () async {
      Map<dynamic, dynamic>? payload;
      messenger.setMockMethodCallHandler(command, (call) async {
        payload = (call.arguments as Map)['payload'] as Map;
        return null;
      });
      await engine.synthesize(
        SpeechRequest(
          requestId: 'r1',
          token: SessionToken('s', 1),
          start: locator(0),
          end: locator(2),
          text: '21',
          synthesisText: 'vingt-et-un',
          voiceId: 'estelle',
          bundleId: 'bundle',
        ),
      );
      expect(payload!['text'], '21');
      expect(payload!['synthesisText'], 'vingt-et-un');
      expect((payload!['end'] as Map)['offsetUtf16'], 2);
    },
  );
}
