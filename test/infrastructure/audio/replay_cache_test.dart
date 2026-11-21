import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/infrastructure/files/audio_cache.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';

import '../speech/platform_speech_engine_test.dart' show wavFixture;

void main() {
  late Directory dir;
  late PrivateFileStore files;
  late AudioCache cache;
  Locator at(int n) =>
      Locator(textId: 't', corpusVersion: 1, passageId: 'p', offsetUtf16: n);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('replay-cache-');
    dir = Directory(await dir.resolveSymbolicLinks());
    files = await PrivateFileStore.open(dir);
    cache = AudioCache(files);
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test(
    'replay requires the exact recorded PCM digest, not just a valid header',
    () async {
      final key = 'a' * 64;
      await files.writeAudioCache(key, wavFixture());
      expect(await cache.lookup(key, at(0), at(5)), isNotNull);
      final bytes = wavFixture()..[44] = 1;
      await File('${dir.path}/cache/audio/$key.wav').writeAsBytes(bytes);
      expect(await cache.lookup(key, at(0), at(5)), isNull);
    },
  );
  test(
    'eviction survives new cache instances and never removes a leased object',
    () async {
      final a = 'a' * 64, b = 'b' * 64;
      await files.writeAudioCache(a, wavFixture());
      await files.writeAudioCache(b, wavFixture());
      final lease = await files.acquire('cache/audio/$a.wav');
      try {
        final removed = await files.trimAudioCache(maxObjects: 1);
        expect(removed, [b]);
        expect(await AudioCache(files).lookup(a, at(0), at(5)), isNotNull);
        expect(await files.exists('cache/audio/$b.integrity.json'), isFalse);
      } finally {
        lease.release();
      }
      await cache.remove(a);
      expect(await files.exists('cache/audio/$a.integrity.json'), isFalse);
    },
  );
}
