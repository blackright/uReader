import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/infrastructure/database/bookmark_repository.dart';
import 'package:prototype/infrastructure/database/book_position_repository.dart';
import 'package:prototype/domain/content.dart' show ReadingMode;
import 'package:prototype/domain/storage.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/content_source_adapter.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';

import '../listening/playback_coordinator_test.dart'
    show RecordingSpeech, RecordingPlayer;

import 'package:prototype/features/library/book_removal_service.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';
import 'package:prototype/infrastructure/database/book_operation_repository.dart';
import 'package:prototype/infrastructure/files/book_operation_reconciler.dart';

import '../book_reader/reader_fixture.dart';

void main() {
  test('deleting the active book allows the next one to play; another deletion leaves it playing', () async {
    final f = ReaderFixture();
    await f.open();
    addTearDown(f.close);
    final a = await f.book('active-a'),
        b = await f.book('active-b'),
        c = await f.book('other-c');
    final marks = BookmarkRepository(f.db, f.content);
    BookLocator at(ContentKey key) =>
        BookLocator(key: key, chapterId: 'c0', blockId: 'b0', offsetUtf16: 0);
    await marks.add(at(a));
    final kept = await marks.add(at(b));
    await marks.add(at(c));
    final positions = BookPositionRepository(f.db, f.content);
    await positions.save(at(b), ReadingMode.visual, expectedRevision: 0);
    final sentinel = File('${f.dir.path}/voice-sentinel.bin');
    await sentinel.writeAsBytes([4, 5, 6]);
    final speech = RecordingSpeech(), player = RecordingPlayer();
    final owner = PlaybackCoordinator(
      speech: speech,
      player: player,
      segmenter: SpeechSegmenter((s) async => 1),
      prepareEngine: () => speech.loadBundle(
        BundleDescriptor(
          id: 'fr-official-aligned',
          version: 'v1',
          manifestDigest: 'a' * 64,
          files: [
            BundleFile(relativePath: 'model', byteSize: 1, sha256: 'b' * 64),
          ],
        ),
      ),
      discardAudio: (_) async {},
      saveBookAudioPosition: (context, locator, current) async {
        await context.toBook(locator);
      },
    );
    addTearDown(owner.close);
    final journal = BookOperationRepository(f.db), repo = BookRepository(f.db);
    final service = BookRemovalService(
      journal: journal,
      files: f.content.files,
      reconciler: BookOperationReconciler(
        repo,
        journal,
        f.content.files,
        purgeAudio: (_) async {},
      ),
      releaseTarget: (key) async {
        await marks.flush();
        await owner.releaseBook(key);
      },
    );
    addTearDown(service.close);
    Future<void> play(ContentKey key) async {
      await owner.playBook(
        BookSpeechContext(key, f.content),
        from: BookLocator(
          key: key,
          chapterId: 'c0',
          blockId: 'b0',
          offsetUtf16: 0,
        ),
      );
      speech.complete(speech.requests.last.requestId);
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(owner.state, PlaybackState.playing);
    }

    await play(a);
    await service.remove(a, confirmed: true);
    expect(owner.state, PlaybackState.stopped);
    expect(owner.positionError, isNull);
    await play(b);
    await service.remove(c, confirmed: true);
    expect(player.playing, true);
    expect(owner.bookKey, b);
    expect(owner.state, PlaybackState.playing);
    expect((await marks.list(b)).items.single.id, kept.bookmark.id);
    expect(
      (await f.db.customSelect('SELECT * FROM book_bookmarks').get()).length,
      1,
    );
    expect(
      (await positions.read(b, ReadingMode.visual))!.locator.blockId,
      'b0',
    );
    expect(await sentinel.readAsBytes(), [4, 5, 6]);
  });
  test('cancel changes nothing; confirmation waits for leases and removes only its target', () async {
    final f = ReaderFixture();
    await f.open();
    addTearDown(f.close);
    final a = await f.book('remove-a'), b = await f.book('keep-b');
    final books = BookRepository(f.db), journal = BookOperationRepository(f.db);
    final stopped = <String>[];
    final reconciler = BookOperationReconciler(
      books,
      journal,
      f.content.files,
      purgeAudio: (key) async {},
    );
    final service = BookRemovalService(
      journal: journal,
      files: f.content.files,
      reconciler: reconciler,
      releaseTarget: (key) async {
        stopped.add(key.id);
      },
    );
    expect(await service.remove(a, confirmed: false), false);
    expect(stopped, isEmpty);
    final lease = await f.content.acquire(a);
    final removal = service.remove(a, confirmed: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((await books.readyPage()).map((b) => b.key.id), [b.id]);
    lease.release();
    expect(await removal, true);
    expect(stopped, [a.id]);
    expect((await books.readyPage()).single.key, b);
    expect(await journal.pending(), isEmpty);
    await service.close();
  });
}
