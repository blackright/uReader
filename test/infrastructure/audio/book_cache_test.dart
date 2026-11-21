import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/infrastructure/database/book_audio_cache_repository.dart';
import 'package:prototype/infrastructure/files/audio_cache.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';

import '../../features/book_reader/reader_fixture.dart';

void main() {
  test('large targeted purge retries after a leased entry without touching another book', () async {
    final f = ReaderFixture();
    await f.open();
    addTearDown(f.close);
    final a = await f.book('many-a'), b = await f.book('many-b');
    final index = BookAudioCacheRepository(f.db),
        files = await PrivateFileStore.open(f.dir);
    final cache = AudioCache(files, onRemoved: index.forget);
    for (var i = 0; i < 130; i++) {
      final key = i.toRadixString(16).padLeft(64, '0'),
          owner = i == 129 ? b : a;
      await files.writeAudioCache(key, Uint8List(46));
      await f.db.customStatement(
        "INSERT INTO book_audio_cache VALUES (?,?,1,'estelle','bundle','v1','v1','{}',46,?,1)",
        [key, owner.id, 'cache/audio/$key.wav'],
      );
    }
    final lastA = 128.toRadixString(16).padLeft(64, '0');
    final lease = await files.acquire('cache/audio/$lastA.wav');
    await expectLater(index.purge(a, cache), throwsA(anything));
    expect(
      (await f.db.customSelect('SELECT * FROM book_audio_cache').get()).length,
      2,
    );
    lease.release();
    await index.purge(a, cache);
    expect(
      (await f.db.customSelect('SELECT book_id FROM book_audio_cache').get())
          .single
          .read<String>('book_id'),
      b.id,
    );
  });
  test(
    'owner and version isolate cache keys; a lease prevents targeted purge',
    () async {
      final f = ReaderFixture();
      await f.open();
      addTearDown(f.close);
      final a = await f.book('cache-a'), b = await f.book('cache-b');
      final index = BookAudioCacheRepository(f.db);
      final files = await PrivateFileStore.open(f.dir);
      final cache = AudioCache(files, onRemoved: index.forget);
      String key(ContentKey owner) => AudioCache.key(
        bundleDigest: 'a' * 64,
        voice: 'estelle',
        text: 'same',
        normalizerVersion: 'v1',
        owner: owner,
      );
      expect(key(a), isNot(key(b)));
      expect(key(a), isNot(key(ContentKey(ContentKind.book, a.id, 2))));
      final bundle = BundleDescriptor(
        id: 'bundle',
        version: 'v1',
        manifestDigest: 'a' * 64,
        files: [
          BundleFile(relativePath: 'model', byteSize: 1, sha256: 'b' * 64),
        ],
      );
      for (final owner in [a, b]) {
        Locator at(int offset) => Locator(
          textId: 'wire',
          corpusVersion: 1,
          passageId: 'b0',
          offsetUtf16: offset,
        );
        final output = SpeechOutput(
          audioHandle: key(owner),
          sampleRate: 24000,
          channels: 1,
          encoding: AudioEncoding.pcm16,
          durationMs: 0,
          byteSize: 46,
          start: at(0),
          end: at(1),
        );
        final request = SpeechRequest(
          requestId: 'r',
          token: SessionToken('s', 1),
          start: at(0),
          end: at(1),
          text: 'x',
          voiceId: 'estelle',
          bundleId: 'bundle',
          bookOwner: owner,
        );
        // Private storage/index lifecycle only; WAV parsing has separate adapter tests.
        await files.writeAudioCache(key(owner), Uint8List(46));
        await index.record(key(owner), request, output, bundle);
      }
      final lease = await files.acquire('cache/audio/${key(a)}.wav');
      await expectLater(index.purge(a, cache), throwsA(anything));
      expect(
        (await f.db.customSelect('SELECT * FROM book_audio_cache').get())
            .length,
        2,
      );
      lease.release();
      await index.purge(a, cache);
      final remaining = await f.db
          .customSelect('SELECT book_id FROM book_audio_cache')
          .get();
      expect(remaining.single.read<String>('book_id'), b.id);
      expect(await files.audioCacheFile(key(b)), isNotNull);
      await f.db.customStatement(
        "INSERT INTO book_positions VALUES (?,'audio',1,'c0','b0',0,1,1)",
        [b.id],
      );
      final removal = JournalOperation(
        id: 'remove-voice',
        kind: OperationKind.delete,
        bundleId: bundle.id,
        bundleVersion: bundle.version,
        manifestDigest: bundle.manifestDigest,
      );
      await f.db.saveOperation(removal);
      await files.delete('cache/audio');
      await f.db.completeDelete(removal);
      expect(
        await f.db.customSelect('SELECT * FROM book_audio_cache').get(),
        isEmpty,
      );
      expect(
        (await f.db
                .customSelect("SELECT * FROM book_positions WHERE mode='audio'")
                .get())
            .length,
        1,
      );
    },
  );
}
