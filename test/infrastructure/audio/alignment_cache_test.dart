import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/word_alignment.dart';
import 'package:prototype/infrastructure/audio/alignment_cache.dart';
import 'package:prototype/infrastructure/files/audio_cache.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';

void main() {
  late Directory dir;
  late PrivateFileStore files;
  late AlignmentCache sidecars;
  final key = 'd' * 64;
  final wav = Uint8List(44 + 2400 * 2);
  WordAlignment alignment({String? sha}) => WordAlignment(
    audioSha256: sha ?? sha256.convert(wav).toString(),
    sourceSha256: 'b' * 64,
    preparedSha256: 'c' * 64,
    passageId: 'p',
    sourceStart: 4,
    sourceEnd: 8,
    samples: 2400,
    alignerVersion: 'attention-l3h9-v1',
    normalizerVersion: 'fr-numbers-v3',
    preparerVersion: 'prepared-map-v1',
    cues: [WordCue(0, 2400, SourceSpan(4, 8))],
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('alignment-cache-');
    dir = Directory(await dir.resolveSymbolicLinks());
    files = await PrivateFileStore.open(dir);
    sidecars = AlignmentCache(files);
    await files.writeAudioCache(key, wav);
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test('published sidecar round trips only with its exact WAV', () async {
    await sidecars.publish(key, alignment());
    expect((await sidecars.read(key))!.cues.single.source.start, 4);
    await files.writeAudioCache(key, Uint8List(wav.length));
    expect(
      await sidecars.read(key),
      isNull,
    ); // republishing invalidates derived metadata.
  });
  test('wrong WAV hash cannot be published', () async {
    await expectLater(
      sidecars.publish(key, alignment(sha: 'a' * 64)),
      throwsA(anything),
    );
    expect(await sidecars.read(key), isNull);
  });
  test(
    'lease prevents replacing or removing either part of the object',
    () async {
      await sidecars.publish(key, alignment());
      final lease = await files.acquire('cache/audio/$key.wav');
      try {
        await expectLater(AudioCache(files).remove(key), throwsA(anything));
        await expectLater(
          sidecars.publish(key, alignment()),
          throwsA(anything),
        );
        expect(await sidecars.read(key), isNotNull);
      } finally {
        lease.release();
      }
      await AudioCache(files).remove(key);
      expect(await files.exists('cache/audio/$key.wav'), isFalse);
      expect(await files.exists('cache/audio/$key.alignment.json'), isFalse);
    },
  );
  test('corrupt or oversized sidecars degrade to unavailable', () async {
    await File('${dir.path}/cache/audio/$key.alignment.json')
        .writeAsString('{bad');
    expect(await sidecars.read(key), isNull);
    await expectLater(
      files.writeAlignmentCache(
        key,
        Uint8List(1048577),
        alignment().audioSha256,
      ),
      throwsA(anything),
    );
  });
  test(
    'wire decoding refuses excess intervals and nonintegral coordinates',
    () {
      final encoded = AlignmentCache.encode(alignment());
      expect(
        () => AlignmentCache.decode({
          ...encoded,
          'cues': [
            [0, 1, 4.5, 8],
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => AlignmentCache.decode({
          ...encoded,
          'cues': List.filled(4097, [0, 1, 4, 8]),
        }),
        throwsFormatException,
      );
    },
  );
}
