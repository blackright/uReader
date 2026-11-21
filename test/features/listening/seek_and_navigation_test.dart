import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';

import 'playback_coordinator_test.dart' show RecordingSpeech, RecordingPlayer;

void main() {
  final text = DemoText(
    id: 't',
    corpusVersion: 1,
    title: 'Test',
    passages: [
      Passage(id: 'p1', textId: 't', ordinal: 0, text: 'Bonjour.'),
      Passage(id: 'p2', textId: 't', ordinal: 1, text: 'Le jardin.'),
    ],
  );
  Locator at(String p) =>
      Locator(textId: 't', corpusVersion: 1, passageId: p, offsetUtf16: 0);
  for (var repeat = 0; repeat < 5; repeat++) {
    test(
      'text change and stop reject both pending generations $repeat',
      () async {
        final speech = RecordingSpeech();
        final player = RecordingPlayer();
        final other = DemoText(
          id: 'other',
          corpusVersion: 1,
          title: 'Autre',
          passages: [
            Passage(
              id: 'other-p',
              textId: 'other',
              ordinal: 0,
              text: 'Un autre texte.',
            ),
          ],
        );
        final owner = PlaybackCoordinator(
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
        addTearDown(owner.close);
        await owner.play(text);
        final first = speech.requests.last;
        await owner.play(other);
        final second = speech.requests.last;
        await owner.stop();
        speech.complete(first.requestId, simulateLateResult: true);
        speech.complete(second.requestId, simulateLateResult: true);
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(player.opens, 0);
        expect(owner.playedLocator, isNull);
        expect(owner.state, PlaybackState.stopped);
      },
    );
    test(
      'seek fences late output and navigation respects bounds $repeat',
      () async {
        final speech = RecordingSpeech();
        final player = RecordingPlayer();
        final saved = <Locator>[];
        final owner = PlaybackCoordinator(
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
          saveAudioPosition: (t, l, current) async {
            if (current()) saved.add(l);
            return l;
          },
        );
        addTearDown(owner.close);
        await owner.play(text);
        final old = speech.requests.last;
        await owner.play(text, from: at('p2'));
        speech.complete(old.requestId, simulateLateResult: true);
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(player.opens, 0);
        expect(saved, isEmpty);
        final next = speech.requests.last;
        expect(next.start.passageId, 'p2');
        speech.complete(next.requestId);
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(saved.single.passageId, 'p2');
        await owner.next();
        expect(owner.state, PlaybackState.completed);
        await owner.play(text, from: at('p1'));
        await owner.previous();
        expect(speech.requests.last.start.passageId, 'p1');
      },
    );
  }

  test('failed durable write leaves real playback and last confirmed position distinct', () async {
    final speech = RecordingSpeech();
    final player = RecordingPlayer();
    var failSave = true;
    final owner = PlaybackCoordinator(
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
      saveAudioPosition: (t, l, current) async {
        if (failSave) throw StateError('injected storage failure');
        return current() ? l : null;
      },
    );
    addTearDown(owner.close);
    await owner.play(text);
    speech.complete(speech.requests.first.requestId);
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(owner.state, PlaybackState.playing);
    expect(owner.playedLocator, isNotNull);
    expect(owner.durableLocator, isNull);
    expect(owner.positionError, isNotNull);
    failSave = false;
    await owner.pause();
    expect(owner.durableLocator!.passageId, 'p1');
    expect(owner.positionError, isNull);
  });
}
