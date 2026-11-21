import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/domain/word_alignment.dart';
import 'package:prototype/features/book_reader/book_follow_binding.dart';
import 'package:prototype/features/book_reader/follow_controller.dart';
import 'package:prototype/features/listening/content_source_adapter.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';

import '../listening/playback_coordinator_test.dart'
    show RecordingPlayer, RecordingSpeech;
import 'reader_fixture.dart';

class ClockPlayer extends RecordingPlayer implements PlayerClock {
  final samples = StreamController<PlayerClockSample>.broadcast(sync: true);
  @override
  Stream<PlayerClockSample> get clockSamples => samples.stream;
  @override
  Future<void> dispose() async {
    await samples.close();
    await super.dispose();
  }
}

Future<void> flushFollow() async {
  for (var i = 0; i < 60; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  for (final delayed in [false, true]) {
    test(delayed ? 'late alignment after stop cannot revive a retired session' : 'clock updates heard offset; consultation policy never seeks or starts audio', () async {
      final fixture = ReaderFixture();
      await fixture.open();
      final key = await fixture.book(
        'follow',
        blocks: 1,
        chapters: 1,
        text: 'Bonjour.',
      );
      final speech = RecordingSpeech(), player = ClockPlayer();
      final owner = PlaybackCoordinator(
        speech: speech,
        player: player,
        segmenter: SpeechSegmenter((_) async => 1),
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
      final follow = FollowController(wordAlignmentAvailable: true);
      final pending = Completer<WordAlignment?>();
      WordAlignment metadata() {
        final r = speech.requests.first;
        return WordAlignment(
          audioSha256: 'a' * 64,
          sourceSha256: sha256.convert(utf8.encode(r.text)).toString(),
          preparedSha256: sha256
              .convert(utf8.encode(r.synthesisText))
              .toString(),
          passageId: r.start.passageId,
          sourceStart: r.start.offsetUtf16,
          sourceEnd: r.end.offsetUtf16,
          samples: 2400,
          alignerVersion: 'attention-l3h9-v1',
          normalizerVersion: 'fr-numbers-v3',
          preparerVersion: 'prepared-map-v1',
          cues: [WordCue(0, 2400, SourceSpan(0, 7))],
        );
      }

      final binding = BookFollowBinding(
        key: key,
        playback: owner,
        follow: follow,
        loadAlignment: (_) =>
            delayed ? pending.future : Future.value(metadata()),
      );
      try {
        await owner.playBook(
          BookSpeechContext(key, fixture.content),
          from: BookLocator(
            key: key,
            chapterId: 'c0',
            blockId: 'b0',
            offsetUtf16: 0,
          ),
        );
        speech.complete(speech.requests.first.requestId);
        await flushFollow();
        expect(owner.state, PlaybackState.playing);
        final token = owner.activePlayerToken;
        if (delayed) {
          await owner.stop();
          pending.complete(metadata());
          await flushFollow();
          expect(follow.active, isNull);
          expect(follow.mode, FollowMode.unavailable);
        } else {
          final opens = player.opens;
          follow.navigation(ReaderNavigationOrigin.user);
          follow.resume();
          expect(player.opens, opens);
          expect(player.playing, isTrue);
          player.samples.add(
            PlayerClockSample(
              token: token,
              segmentId: 'fake-audio',
              audioSha256: 'a' * 64,
              position: const Duration(milliseconds: 10),
              state: PlayerClockState.playing,
              monotonicMicros: 1,
            ),
          );
          expect(follow.active!.start, 0);
          expect(owner.playedLocator!.passageId, 'b0');
          await owner.stop();
          expect(follow.active, isNull);
        }
      } finally {
        await binding.close();
        follow.dispose();
        await owner.close();
        await fixture.close();
      }
    });
  }
}
