import 'package:audio_service/audio_service.dart' show AudioProcessingState;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';
import 'package:prototype/infrastructure/audio/system_audio_handler.dart';

import '../../features/listening/playback_coordinator_test.dart'
    show RecordingSpeech, RecordingPlayer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlaybackCoordinator owner;
  late SystemAudioHandler handler;
  setUp(() {
    final speech = RecordingSpeech();
    owner = PlaybackCoordinator(
      speech: speech,
      player: RecordingPlayer(),
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
    );
    handler = SystemAudioHandler(owner);
  });
  tearDown(() async {
    await handler.close();
    await owner.close();
  });

  test(
    'startup and media button without selection never start audio',
    () async {
      await handler.play();
      expect(owner.state, PlaybackState.stopped);
      expect(handler.playbackState.value.playing, isFalse);
      expect(
        handler.playbackState.value.processingState,
        AudioProcessingState.idle,
      );
    },
  );

  test('UI and system share preparation, pause and stop state', () async {
    final text = DemoText(
      id: 't',
      corpusVersion: 1,
      title: 'Test',
      passages: [Passage(id: 'p', textId: 't', ordinal: 0, text: 'Bonjour.')],
    );
    // State changes are synchronous, before the fake engine can fail its request.
    final pending = owner.play(text);
    expect(handler.playbackState.value.playing, isTrue);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.buffering,
    );
    await handler.pause();
    await pending;
    await handler.stop();
    expect(owner.state, PlaybackState.stopped);
    expect(handler.playbackState.value.playing, isFalse);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  test('task removal stops the existing owner', () async {
    await handler.onTaskRemoved();
    expect(owner.state, PlaybackState.stopped);
    expect(
      handler.playbackState.value.processingState,
      AudioProcessingState.idle,
    );
  });

  test(
    'native idle cleanup preserves a preparation failure for the UI',
    () async {
      final text = DemoText(
        id: 't',
        corpusVersion: 1,
        title: 'Test',
        passages: [Passage(id: 'p', textId: 't', ordinal: 0, text: 'Bonjour.')],
      );
      await owner.play(text);
      final speech = owner.speech as RecordingSpeech;
      speech.fail(speech.requests.single.requestId);
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(owner.state, PlaybackState.error);
      await handler.stop();
      expect(owner.state, PlaybackState.error);
      expect(owner.error, isNotNull);
    },
  );
}
