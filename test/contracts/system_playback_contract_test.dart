import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';
import 'package:prototype/infrastructure/audio/audio_interruption_policy.dart';
import 'package:prototype/infrastructure/audio/system_audio_handler.dart';

import '../features/listening/playback_coordinator_test.dart'
    show RecordingSpeech, RecordingPlayer;

void main() {
  late RecordingSpeech speech;
  late RecordingPlayer player;
  late PlaybackCoordinator owner;
  late SystemAudioHandler handler;
  late AudioInterruptionPolicy policy;
  late StreamController<bool> interruptions;
  late StreamController<void> noisy;
  var focusGranted = true;
  final text = DemoText(
    id: 't',
    corpusVersion: 1,
    title: 'Test',
    passages: [
      Passage(id: 'p', textId: 't', ordinal: 0, text: 'Bonjour le jardin.'),
    ],
  );
  Future<void> settle() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    focusGranted = true;
    speech = RecordingSpeech();
    player = RecordingPlayer();
    owner = PlaybackCoordinator(
      speech: speech,
      player: player,
      segmenter: SpeechSegmenter((s) async => s.length),
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
      requestAudioFocus: () async => focusGranted,
    );
    handler = SystemAudioHandler(owner);
    interruptions = StreamController<bool>.broadcast(sync: true);
    noisy = StreamController<void>.broadcast(sync: true);
    policy = AudioInterruptionPolicy(
      owner: owner,
      interruptions: interruptions.stream,
      noisy: noisy.stream,
    );
  });
  tearDown(() async {
    await policy.close();
    await handler.close();
    await owner.close();
    await interruptions.close();
    await noisy.close();
  });

  test(
    'interruption while preparing blocks late output until manual resume',
    () async {
      await owner.play(text);
      interruptions.add(true);
      speech.complete(speech.requests.single.requestId);
      await settle();
      expect(owner.state, PlaybackState.paused);
      expect(player.opens, 0);
      interruptions.add(false);
      await settle();
      expect(player.playing, isFalse);
      await handler.play();
      await settle();
      expect(player.opens, 1);
      expect(player.playing, isTrue);
      expect(owner.state, PlaybackState.playing);
    },
  );

  test('noisy pauses once and output cannot restart itself', () async {
    await owner.play(text);
    speech.complete(speech.requests.single.requestId);
    await settle();
    noisy.add(null);
    noisy.add(null);
    await settle();
    expect(player.playing, isFalse);
    expect(owner.state, PlaybackState.paused);
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('system stop rejects a pending old generation', () async {
    await owner.play(text);
    final request = speech.requests.single;
    await handler.stop();
    speech.complete(request.requestId, simulateLateResult: true);
    await settle();
    expect(player.opens, 0);
    expect(owner.state, PlaybackState.stopped);
  });

  test('focus refusal retains prepared output for explicit retry', () async {
    focusGranted = false;
    await owner.play(text);
    speech.complete(speech.requests.single.requestId);
    await settle();
    expect(owner.state, PlaybackState.paused);
    expect(player.opens, 0);
    focusGranted = true;
    await settle();
    expect(player.opens, 0);
    await handler.play();
    await settle();
    expect(owner.state, PlaybackState.playing);
    expect(player.opens, 1);
  });

  test('pause fences an in-flight focus grant', () async {
    await policy.close();
    await handler.close();
    await owner.close();
    final grant = Completer<bool>();
    final engine = RecordingSpeech();
    player = RecordingPlayer();
    owner = PlaybackCoordinator(
      speech: engine,
      player: player,
      segmenter: SpeechSegmenter((s) async => s.length),
      prepareEngine: () => engine.loadBundle(
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
      requestAudioFocus: () => grant.future,
    );
    handler = SystemAudioHandler(owner);
    policy = AudioInterruptionPolicy(
      owner: owner,
      interruptions: interruptions.stream,
      noisy: noisy.stream,
    );
    await owner.play(text);
    engine.complete(engine.requests.single.requestId);
    await settle();
    final paused = handler.pause();
    grant.complete(true);
    await paused;
    await settle();
    expect(owner.state, PlaybackState.paused);
    expect(player.opens, 0);
  });
}
