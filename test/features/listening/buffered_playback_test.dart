import 'package:prototype/domain/books.dart';
import 'package:prototype/features/listening/content_source_adapter.dart';

import '../book_reader/reader_fixture.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';

import 'playback_coordinator_test.dart' show RecordingPlayer, RecordingSpeech;

class QueuePlayer extends RecordingPlayer implements BufferedAudioPlayer {
  final queue = <SessionToken>[];
  int stops = 0;
  @override
  bool isCurrent(SessionToken value) => token?.matches(value) == true;
  @override
  Future<void> open(String handle, SessionToken value) async {
    await super.open(handle, value);
    queue
      ..clear()
      ..add(value);
  }

  @override
  Future<void> append(String handle, SessionToken value) async {
    queue.add(value);
  }

  @override
  bool contains(SessionToken value) => queue.any((v) => v.matches(value));
  @override
  Future<void> retire(SessionToken value) async {
    queue.removeWhere((v) => v.matches(value));
  }

  @override
  Future<void> stop() async {
    stops++;
    queue.clear();
    await super.stop();
  }

  void advance() {
    final old = token!, at = queue.indexWhere((v) => v.matches(old));
    controller.add(PlayerEvent(PlayerEventKind.completed, old));
    if (at >= 0 && at + 1 < queue.length) {
      token = queue[at + 1];
      controller.add(PlayerEvent(PlayerEventKind.started, token!));
    }
  }
}

Future<void> pumpProducer() async {
  for (var i = 0; i < 80; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  int held = 0;
  late RecordingSpeech speech;
  late QueuePlayer player;
  late PlaybackCoordinator owner;
  DemoText text(int passages) => DemoText(
    id: 't',
    corpusVersion: 1,
    title: 'Test',
    passages: [
      for (var i = 0; i < passages; i++)
        Passage(id: 'p$i', textId: 't', ordinal: i, text: 'Bonjour jardin.'),
    ],
  );
  setUp(() {
    held = 0;
    speech = RecordingSpeech();
    player = QueuePlayer();
    owner = PlaybackCoordinator(
      speech: speech,
      player: player,
      segmenter: SpeechSegmenter((_) async => 2),
      discardAudio: (_) async {},
      holdPreparedAudio: (_) async {
        held++;
        return () {
          held--;
        };
      },
      initialBuffer: const Duration(milliseconds: 20),
      targetBuffer: const Duration(milliseconds: 40),
      maxBufferedSegments: 4,
      adaptiveBuffer: false,
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
  });
  tearDown(() async {
    await owner.close();
  });
  Future<void> completeNext() async {
    final r = speech.requests.last;
    speech.complete(r.requestId);
    await pumpProducer();
  }

  test(
    'queued handoff does not stop while native current-source catches up',
    () async {
      await owner.play(text(8));
      await pumpProducer();
      await completeNext();
      await completeNext();
      final previous = player.token!;
      final next = player.queue[1];
      final stops = player.stops;
      player.controller.add(PlayerEvent(PlayerEventKind.completed, previous));
      await pumpProducer();
      expect(
        player.stops,
        stops,
        reason: 'A queued successor is not a buffer underrun',
      );
      player.token = next;
      player.controller.add(PlayerEvent(PlayerEventKind.started, next));
      await pumpProducer();
      expect(player.opens, 1);
      expect(player.queue.any((t) => t.matches(previous)), isFalse);
      expect(owner.playedLocator!.passageId, 'p1');
    },
  );

  test(
    'disk reserve outlives the native playlist window and remains leased',
    () async {
      await owner.close();
      owner = PlaybackCoordinator(
        speech: speech = RecordingSpeech(),
        player: player = QueuePlayer(),
        segmenter: SpeechSegmenter((_) async => 2),
        prepareEngine: () => speech.loadBundle(
          BundleDescriptor(
            id: "fr-official-aligned",
            version: "v1",
            manifestDigest: "a" * 64,
            files: [
              BundleFile(relativePath: "model", byteSize: 1, sha256: "b" * 64),
            ],
          ),
        ),
        discardAudio: (_) async {},
        holdPreparedAudio: (_) async {
          held++;
          return () {
            held--;
          };
        },
        initialBuffer: const Duration(milliseconds: 20),
        targetBuffer: const Duration(milliseconds: 80),
        maxBufferedSegments: 4,
        maxPreparedSegments: 16,
        adaptiveBuffer: false,
      );
      await owner.play(text(8));
      await pumpProducer();
      for (var i = 0; i < 8; i++) {
        await completeNext();
      }
      expect(owner.preparedSegments, 8);
      expect(player.queue.length, 4);
      expect(held, 8);
      for (var i = 0; i < 5; i++) {
        player.advance();
        await pumpProducer();
      }
      expect(player.opens, 1);
      expect(owner.preparedSegments, 3);
      expect(player.queue.length, 3);
      expect(held, 3);
      await owner.stop();
      expect(held, 0);
    },
  );

  test('observed slow synthesis raises the bounded duration target', () async {
    await owner.close();
    owner = PlaybackCoordinator(
      speech: speech = RecordingSpeech(),
      player: player = QueuePlayer(),
      segmenter: SpeechSegmenter((_) async => 2),
      prepareEngine: () => speech.loadBundle(
        BundleDescriptor(
          id: "fr-official-aligned",
          version: "v1",
          manifestDigest: "a" * 64,
          files: [
            BundleFile(relativePath: "model", byteSize: 1, sha256: "b" * 64),
          ],
        ),
      ),
      discardAudio: (_) async {},
      initialBuffer: const Duration(milliseconds: 20),
      targetBuffer: const Duration(milliseconds: 40),
      maxBufferedSegments: 4,
    );
    await owner.play(text(8));
    await pumpProducer();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await completeNext();
    expect(owner.bufferTargetMs, 60);
    expect(player.opens, 0);
  });

  test(
    'starts with actual buffered duration then advances without stop/open',
    () async {
      await owner.play(text(8));
      await pumpProducer();
      await completeNext();
      expect(player.opens, 0);
      await completeNext();
      expect(player.opens, 1);
      expect(owner.state, PlaybackState.playing);
      await completeNext();
      await completeNext();
      expect(owner.preparedSegments, 4);
      expect(speech.requests.length, 4);
      final stops = player.stops;
      player.advance();
      await pumpProducer();
      expect(player.opens, 1);
      expect(player.stops, stops);
      expect(owner.playedLocator!.passageId, 'p1');
      expect(speech.requests.length, 5);
    },
  );
  test(
    'paused preparation never starts sound; resume preserves prepared queue',
    () async {
      await owner.play(text(4));
      await pumpProducer();
      await owner.pause();
      await completeNext();
      await completeNext();
      expect(player.opens, 0);
      expect(player.playing, isFalse);
      await owner.resume();
      await pumpProducer();
      expect(player.opens, 1);
      expect(owner.state, PlaybackState.playing);
    },
  );
  test('short end of book starts below target and finishes without phantom synthesis', () async {
    await owner.play(text(1));
    await pumpProducer();
    await completeNext();
    expect(owner.state, PlaybackState.playing);
    expect(player.opens, 1);
    player.advance();
    await pumpProducer();
    expect(owner.state, PlaybackState.completed);
    expect(speech.requests.length, 1);
  });
  test('chapter preparation finishes before playback and uses a bounded native window', () async {
    Future<void> until(bool Function() ready, String message) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!ready()) {
        if (DateTime.now().isAfter(deadline)) fail(message);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }

    final f = ReaderFixture();
    await f.open();
    final key = await f.book(
      'chapter',
      blocks: 12,
      chapters: 2,
      text: 'Bonjour jardin.',
    );
    try {
      await owner.playBook(
        BookSpeechContext(key, f.content),
        from: BookLocator(
          key: key,
          chapterId: 'c0',
          blockId: 'b0',
          offsetUtf16: 0,
        ),
        prepareChapter: true,
      );
      await pumpProducer();
      for (var i = 0; i < 6; i++) {
        // SQLite runs on another worker; event-loop turns do not guarantee its reply.
        await until(
          () => speech.requests.length > i,
          'Chapter request $i not produced',
        );
        await completeNext();
        if (i < 5) expect(player.opens, 0);
      }
      await until(() => player.opens == 1, 'Prepared chapter did not start');
      expect(speech.requests.length, 6);
      expect(player.opens, 1);
      expect(owner.preparedSegments, 6);
      expect(player.queue.length, 4);
      expect(held, 6);
      for (var i = 0; i < 6; i++) {
        player.advance();
        await pumpProducer();
      }
      expect(owner.state, PlaybackState.completed);
      expect(held, 0);
      expect(speech.requests.length, 6);
    } finally {
      await owner.stop();
      await f.close();
    }
  });
  test('stop fences a pending generation and its late completion', () async {
    await owner.play(text(4));
    await pumpProducer();
    final old = speech.requests.single;
    await owner.stop();
    speech.complete(old.requestId, simulateLateResult: true);
    await pumpProducer();
    expect(player.opens, 0);
    expect(owner.state, PlaybackState.stopped);
    expect(owner.preparedSegments, 0);
  });
}
