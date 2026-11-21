// Actual native synthesis and playlist; synthetic text and isolated cache only.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';
import 'package:prototype/features/model_setup/model_catalog.dart';
import 'package:prototype/infrastructure/audio/local_segment_player.dart';
import 'package:prototype/infrastructure/files/audio_cache.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';
import 'package:prototype/infrastructure/speech/alignment_provider.dart';
import 'package:prototype/infrastructure/speech/platform_speech_engine.dart';

import 'feasibility_bootstrap.dart';

class _ObservedPlayer extends LocalSegmentPlayer {
  _ObservedPlayer(super.cache);
  int opens = 0;
  @override
  Future<void> open(String handle, SessionToken token) async {
    opens++;
    await super.open(handle, token);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('generate ahead during actual continuous playback', (
    tester,
  ) async {
    await waitForNative(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Essai de lecture continue — textes synthétiques'),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      final support = await (await getApplicationSupportDirectory())
          .resolveSymbolicLinks();
      final root = Directory(
        '$support/fluent-playback-${DateTime.now().microsecondsSinceEpoch}',
      );
      final files = await PrivateFileStore.open(root);
      final cache = AudioCache(files);
      final bytes = await rootBundle.load('assets/models/manifest.json');
      final catalog = ModelCatalog.fromBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      expect(catalog.alignmentAvailable, isTrue);
      var generatedMs = 0, generated = 0, clockSamples = 0;
      final speech = PlatformSpeechEngine(
        cache,
        alignmentProvider: const AttentionAlignmentProvider(enabled: true),
        onPublished: (key, request, output, bundle) async {
          generated++;
          generatedMs += output.durationMs;
        },
      );
      final player = _ObservedPlayer(cache);
      final owner = PlaybackCoordinator(
        speech: speech,
        player: player,
        segmenter: SpeechSegmenter(speech.tokenCount),
        prepareEngine: () => speech.loadBundle(catalog.bundle),
        discardAudio: cache.retainForReplay,
        releaseAudioBatch: (_) => cache.trimReplay(),
        holdPreparedAudio: (key) async {
          final lease = await files.acquire('cache/audio/$key.wav');
          return lease.release;
        },
      );
      final finished = Completer<void>();
      final played = <String>{};
      final elapsed = Stopwatch()..start();
      int? startupMs;
      var stalls = 0, highWater = 0;
      var started = false;
      var lastState = PlaybackState.stopped;
      void observe() {
        highWater = highWater > owner.preparedSegments
            ? highWater
            : owner.preparedSegments;
        if (owner.state == PlaybackState.playing) {
          started = true;
          startupMs ??= elapsed.elapsedMilliseconds;
          if (owner.playedLocator != null)
            played.add(owner.playedLocator!.passageId);
        }
        if (started &&
            owner.state == PlaybackState.preparing &&
            lastState != owner.state)
          stalls++;
        lastState = owner.state;
        if (!finished.isCompleted && owner.state == PlaybackState.completed)
          finished.complete();
        if (!finished.isCompleted && owner.state == PlaybackState.error) {
          finished.completeError(
            StateError('Playback failed: ${owner.error?.code}'),
          );
        }
      }

      final clock = player.clockSamples.listen((_) {
        clockSamples++;
      });
      owner.addListener(observe);
      const corpus = [
        'Chaque matin, Léa ouvre la petite porte du jardin.',
        'À Noël, Émilie prépare une crème brûlée.',
        'Le chat regarde les oiseaux. Puis il retourne dans la maison.',
      ];
      try {
        await owner.play(
          DemoText(
            id: 'continuous-validation',
            corpusVersion: 1,
            title: 'Lecture continue synthétique',
            passages: [
              for (var i = 0; i < 40; i++)
                Passage(
                  id: 'p$i',
                  textId: 'continuous-validation',
                  ordinal: i,
                  text: corpus[i % corpus.length],
                ),
            ],
          ),
        );
        await finished.future.timeout(const Duration(minutes: 5));
        expect(played.length, 40);
        expect(generated, greaterThanOrEqualTo(40));
        expect(
          player.opens,
          1,
          reason:
              'A reopened playlist indicates starvation or a broken transition',
        );
        expect(stalls, 0);
        expect(clockSamples, greaterThan(0));
        binding.reportData = {
          'status': 'passed',
          'passagesPlayed': played.length,
          'publishedSegments': generated,
          'audioMs': generatedMs,
          'startupMs': startupMs,
          'elapsedMs': elapsed.elapsedMilliseconds,
          'playlistOpens': player.opens,
          'preparingTransitionsAfterStart': stalls,
          'clockSamples': clockSamples,
          'preparedSegmentHighWater': highWater,
          'productDatabaseOpened': false,
          'g1': 'not_evaluated',
          'audibleBoundaryQuality': 'not_evaluated',
        };
      } finally {
        owner.removeListener(observe);
        await clock.cancel();
        await owner.close();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 7)));
}
