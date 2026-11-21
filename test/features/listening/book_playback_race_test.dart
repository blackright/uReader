import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/features/listening/content_source_adapter.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';

import 'playback_coordinator_test.dart' show RecordingPlayer, RecordingSpeech;
import '../book_reader/reader_fixture.dart';

void main() {
  test(
    'end of book releases its content lease without starting another book',
    () async {
      final f = ReaderFixture();
      await f.open();
      addTearDown(f.close);
      final key = await f.book(
        'one-passage',
        blocks: 1,
        chapters: 1,
        text: 'Bonjour.',
      );
      final speech = RecordingSpeech(), player = RecordingPlayer();
      final owner = PlaybackCoordinator(
        speech: speech,
        player: player,
        segmenter: SpeechSegmenter((s) async => 1),
        discardAudio: (_) async {},
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
      );
      addTearDown(owner.close);
      await owner.playBook(
        BookSpeechContext(key, f.content),
        from: BookLocator(
          key: key,
          chapterId: 'c0',
          blockId: 'b0',
          offsetUtf16: 0,
        ),
      );
      await expectLater(f.content.files.removeBook(key.id), throwsA(anything));
      speech.complete(speech.requests.single.requestId);
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(owner.state, PlaybackState.playing);
      player.complete();
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(owner.state, PlaybackState.completed);
      expect(speech.requests.length, 1);
      expect(owner.retainedBookSegments, 0);
      await f.content.files.removeBook(key.id);
    },
  );
  for (var run = 0; run < 5; run++) {
    for (var scenario = 0; scenario < 5; scenario++) {
      test('book control scenario $scenario round $run', () async {
        final f = ReaderFixture();
        await f.open();
        addTearDown(f.close);
        final first = await f.book('first', text: 'Bonjour. La suite.');
        final second = await f.book('second', text: 'Autre livre.');
        final speech = RecordingSpeech(), player = RecordingPlayer();
        final owner = PlaybackCoordinator(
          speech: speech,
          player: player,
          segmenter: SpeechSegmenter((s) async => s.split(' ').length),
          prepareEngine: () => speech.loadBundle(
            BundleDescriptor(
              id: 'fr-official-aligned',
              version: 'v1',
              manifestDigest: 'a' * 64,
              files: [
                BundleFile(relativePath: 'test', byteSize: 1, sha256: 'b' * 64),
              ],
            ),
          ),
          discardAudio: (_) async {},
        );
        addTearDown(owner.close);
        BookLocator at(ContentKey key) => BookLocator(
          key: key,
          chapterId: 'c0',
          blockId: 'b0',
          offsetUtf16: 0,
        );
        await owner.playBook(
          BookSpeechContext(first, f.content),
          from: at(first),
        );
        final old = speech.requests.last;
        if (scenario == 0) {
          await owner.pause();
          speech.complete(old.requestId);
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(Duration.zero);
          }
          expect(player.opens, 0);
          expect(owner.playedLocator, isNull);
          await owner.resume();
          for (var i = 0; i < 20; i++) {
            await Future<void>.delayed(Duration.zero);
          }
          expect(player.opens, 1);
          expect(owner.playedLocator, isNotNull);
        } else if (scenario == 1) {
          await owner.stop();
          speech.complete(old.requestId, simulateLateResult: true);
        } else if (scenario == 2) {
          await owner.playBook(
            BookSpeechContext(second, f.content),
            from: at(second),
          );
          speech.complete(old.requestId, simulateLateResult: true);
          expect(owner.bookKey, second);
        } else if (scenario == 3) {
          await owner.playBook(
            BookSpeechContext(first, f.content),
            from: BookLocator(
              key: first,
              chapterId: 'c0',
              blockId: 'b1',
              offsetUtf16: 0,
            ),
          );
          speech.complete(old.requestId, simulateLateResult: true);
          expect(speech.requests.last.start.passageId, 'b1');
        } else {
          await owner.close();
          await f.db.customStatement(
            "UPDATE books SET state='deleting' WHERE book_id='first'",
          );
          await expectLater(
            f.content.acquire(first),
            throwsA(isA<BookFailure>()),
          );
          await owner.playBook(
            BookSpeechContext(first, f.content),
            from: at(first),
          );
          speech.complete(old.requestId, simulateLateResult: true);
          final reopenedSpeech = RecordingSpeech(),
              reopenedPlayer = RecordingPlayer();
          final reopened = PlaybackCoordinator(
            speech: reopenedSpeech,
            player: reopenedPlayer,
            segmenter: SpeechSegmenter((s) async => 1),
            prepareEngine: () async {},
            discardAudio: (_) async {},
          );
          expect(reopened.state, PlaybackState.stopped);
          expect(reopenedSpeech.requests, isEmpty);
          expect(reopenedPlayer.playing, isFalse);
          await reopened.close();
        }
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        if (scenario != 0) {
          expect(player.opens, 0);
          expect(owner.playedLocator, isNull);
        }
        expect(owner.retainedBookSegments, lessThanOrEqualTo(2));
        await owner.stop();
        expect(player.playing, isFalse);
        if (scenario != 4) expect(owner.state, PlaybackState.stopped);
      });
    }
  }
}
