import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';

import '../../fakes/fake_speech_engine.dart';

class RecordingSpeech extends FakeSpeechEngine {
  final requests = <SpeechRequest>[];
  @override
  Future<void> synthesize(SpeechRequest request) async {
    requests.add(request);
    await super.synthesize(request);
  }
}

class RecordingPlayer implements AudioPlayer {
  final controller = StreamController<PlayerEvent>.broadcast(sync: true);
  SessionToken? token;
  int opens = 0;
  bool playing = false;
  @override
  Stream<PlayerEvent> get events => controller.stream;
  @override
  Future<void> open(String handle, SessionToken value) async {
    token = value;
    opens++;
  }

  @override
  Future<void> play() async {
    playing = true;
    controller.add(PlayerEvent(PlayerEventKind.started, token!));
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> stop() async {
    playing = false;
  }

  @override
  Future<void> dispose() => controller.close();
  void complete() =>
      controller.add(PlayerEvent(PlayerEventKind.completed, token!));
}

void main() {
  DemoText text([String id = 't']) => DemoText(
    id: id,
    corpusVersion: 1,
    title: 'Test',
    passages: [
      Passage(id: 'p', textId: id, ordinal: 0, text: 'Bonjour le jardin.'),
      // Separate passages keep these transport tests independent of prosody grouping.
      Passage(
        id: 'p-next',
        textId: id,
        ordinal: 1,
        text: 'Voici trois pommes.',
      ),
    ],
  );
  late RecordingSpeech speech;
  late RecordingPlayer player;
  late PlaybackCoordinator coordinator;
  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    speech = RecordingSpeech();
    player = RecordingPlayer();
    coordinator = PlaybackCoordinator(
      speech: speech,
      player: player,
      segmenter: SpeechSegmenter((s) async => s.length),
      discardAudio: (_) async {},
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
    );
  });
  tearDown(() => coordinator.close());

  test(
    'uses the configured voice and bundle without substituting Estelle',
    () async {
      await coordinator.close();
      speech = RecordingSpeech();
      player = RecordingPlayer();
      coordinator = PlaybackCoordinator(
        speech: speech,
        player: player,
        segmenter: SpeechSegmenter((s) async => s.length),
        discardAudio: (_) async {},
        prepareEngine: () => speech.loadBundle(
          BundleDescriptor(
            id: 'fr-kokoro-siwis',
            version: 'v1',
            manifestDigest: 'a' * 64,
            files: [
              BundleFile(relativePath: 'model', byteSize: 1, sha256: 'b' * 64),
            ],
          ),
        ),
        voiceId: 'ff_siwis',
        bundleId: 'fr-kokoro-siwis',
      );
      await coordinator.play(text());
      expect(speech.requests, isNotEmpty);
      expect(speech.requests.single.voiceId, 'ff_siwis');
      expect(speech.requests.single.bundleId, 'fr-kokoro-siwis');
    },
  );

  test(
    'suspending voice fences every entry and requires explicit fresh playback',
    () async {
      await coordinator.play(text());
      await coordinator.suspendVoice();
      final count = speech.requests.length;
      await coordinator.next();
      await coordinator.previous();
      await coordinator.resume();
      await coordinator.play(text());
      expect(speech.requests.length, count);
      expect(player.playing, isFalse);
      coordinator.resumeVoice();
      await coordinator.next();
      expect(speech.requests.length, count);
      await coordinator.play(text());
      expect(speech.requests.length, greaterThan(count));
    },
  );
  test(
    'Appuis répétés, un segment d’avance et fin sans texte suivant',
    () async {
      final preparing = coordinator.play(text());
      await coordinator.play(text());
      await preparing;
      expect(speech.requests.length, 1);
      speech.complete(speech.requests.first.requestId);
      await settle();
      expect(coordinator.state, PlaybackState.playing);
      expect(speech.requests.length, 2);
      speech.complete(speech.requests.last.requestId);
      await settle();
      expect(player.opens, 1);
      player.complete();
      await settle();
      expect(player.opens, 2);
      player.complete();
      await settle();
      expect(coordinator.state, PlaybackState.completed);
      expect(speech.requests.length, 2);
    },
  );
  test(
    'Pause pendant préparation, reprise, arrêt et résultat tardif',
    () async {
      await coordinator.play(text());
      await coordinator.pause();
      speech.complete(speech.requests.first.requestId);
      await settle();
      expect(coordinator.state, PlaybackState.paused);
      expect(player.opens, 0);
      await coordinator.resume();
      await settle();
      expect(coordinator.state, PlaybackState.playing);
      final late = speech.requests.last.requestId;
      await coordinator.stop();
      await coordinator.stop();
      speech.complete(late, simulateLateResult: true);
      await settle();
      expect(coordinator.state, PlaybackState.stopped);
      expect(player.opens, 1);
    },
  );
  test(
    'Changer de texte pendant lecture invalide l’ancienne session',
    () async {
      await coordinator.play(text());
      speech.complete(speech.requests.first.requestId);
      await settle();
      await coordinator.play(text('other'));
      await settle();
      expect(coordinator.textId, 'other');
      expect(coordinator.state, PlaybackState.preparing);
    },
  );
  test('Voix absente : erreur française et aucune lecture', () async {
    await coordinator.close();
    speech = RecordingSpeech();
    player = RecordingPlayer();
    coordinator = PlaybackCoordinator(
      speech: speech,
      player: player,
      segmenter: SpeechSegmenter((s) async => s.length),
      discardAudio: (_) async {},
      prepareEngine: () async => throw const AppError(ErrorCode.modelMissing),
    );
    await coordinator.play(text());
    expect(coordinator.state, PlaybackState.error);
    expect(coordinator.error!.code, ErrorCode.modelMissing);
    expect(player.opens, 0);
  });
  test('Segmentation conserve source et expressions normalisées', () async {
    final original = DemoText(
      id: 't',
      corpusVersion: 1,
      title: 'Test',
      passages: [
        Passage(
          id: 'p',
          textId: 't',
          ordinal: 0,
          text: '📖 Nous achetons 250 grammes de fromage et 21 livres.',
        ),
      ],
    );
    final segments = await SpeechSegmenter(
      (s) async => s.split(' ').length * 10,
    ).segment(original);
    expect(segments.map((s) => s.source).join(), original.passages.single.text);
    expect(
      segments.any(
        (s) => s.synthesis.toLowerCase().contains('deux cent cinquante'),
      ),
      isTrue,
    );
    expect(
      segments.any((s) => s.synthesis.toLowerCase().contains('vingt-et-un')),
      isTrue,
    );
    for (final segment in segments) {
      expect(
        segment.end.offsetUtf16 - segment.start.offsetUtf16,
        segment.source.length,
      );
    }
    await expectLater(
      const SpeechSegmenter(_tooMany).segment(original),
      throwsA(isA<AppError>()),
    );
  });

  test('Échec de la prélecture : arrêt du lecteur et erreur visible', () async {
    await coordinator.play(text());
    speech.complete(speech.requests.first.requestId);
    await settle();
    expect(player.playing, isTrue);
    speech.fail(speech.requests.last.requestId);
    await settle();
    expect(coordinator.state, PlaybackState.error);
    expect(player.playing, isFalse);
  });
  test(
    'Navigation explicite aux bornes, sans démarrer un autre texte',
    () async {
      await coordinator.play(text());
      await coordinator.previous();
      expect(speech.requests.last.start.offsetUtf16, 0);
      speech.complete(speech.requests.last.requestId);
      await settle();
      await coordinator.next();
      speech.complete(speech.requests.last.requestId);
      await settle();
      await coordinator.next();
      expect(coordinator.state, PlaybackState.completed);
      expect(coordinator.textId, 't');
    },
  );
  test('Le domaine refuse un texte vide avant toute synthèse', () {
    expect(
      () =>
          DemoText(id: 'empty', corpusVersion: 1, title: 'Vide', passages: []),
      throwsA(isA<AppError>()),
    );
    expect(speech.requests, isEmpty);
  });
}

Future<int> _tooMany(String _) async => 51;
