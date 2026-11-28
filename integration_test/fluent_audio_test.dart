// Actual native synthesis and playlist; synthetic or explicitly selected installed
// book content, with an isolated cache/catalogue and no saved product positions.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart'
    show AudioService, AudioServiceConfig;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/domain/word_alignment.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';
import 'package:prototype/features/model_setup/model_catalog.dart';
import 'package:prototype/infrastructure/audio/local_segment_player.dart';
import 'package:prototype/infrastructure/audio/system_audio_handler.dart';
import 'package:prototype/infrastructure/audio/audio_interruption_policy.dart';
import 'package:prototype/infrastructure/files/audio_cache.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';
import 'package:prototype/infrastructure/speech/alignment_provider.dart';
import 'package:prototype/infrastructure/speech/platform_speech_engine.dart';
import 'package:prototype/infrastructure/speech/speech_messages.dart';

import 'feasibility_bootstrap.dart';
import 'installed_book_audio_source.dart';

import 'package:prototype/features/listening/content_source_adapter.dart';

class _ObservedPlayer extends LocalSegmentPlayer {
  _ObservedPlayer(super.cache, this.record);
  final void Function(Map<String, Object?>) record;
  int opens = 0;
  @override
  Future<void> open(String handle, SessionToken token) async {
    opens++;
    record({"event": "open", "token": token.sessionId});
    await super.open(handle, token);
  }

  @override
  Future<void> append(String handle, SessionToken token) async {
    record({'event': 'append', 'token': token.sessionId});
    await super.append(handle, token);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const passageCount = int.fromEnvironment("FLUENT_PASSAGES", defaultValue: 40);
  const bookQuery = String.fromEnvironment("FLUENT_BOOK_QUERY");
  const testSeconds = int.fromEnvironment("FLUENT_SECONDS", defaultValue: 0);
  const startAtChapterTail = bool.fromEnvironment("FLUENT_CHAPTER_TAIL");
  testWidgets('generate ahead during actual continuous playback', (
    tester,
  ) async {
    await waitForNative(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Essai de lecture continue'))),
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
      final elapsed = Stopwatch()..start();
      final trace = <Map<String, Object?>>[];
      void record(Map<String, Object?> row) {
        if (trace.length < 2048) {
          trace.add({'atMs': elapsed.elapsedMilliseconds, ...row});
        }
      }

      var tokenCountCalls = 0, tokenCountMs = 0;
      final speech = PlatformSpeechEngine(
        cache,
        nativeEvents: const EventChannel(SpeechMessage.eventChannel)
            .receiveBroadcastStream()
            .map((event) {
              if (event is Map && event['output'] is Map) {
                final metrics = (event['output'] as Map)['timings'];
                if (metrics is Map) {
                  record({
                    'event': 'nativeTiming',
                    'request': event['requestId'],
                    for (final key in [
                      'verificationMs',
                      'initializationMs',
                      'totalMs',
                      'audioMs',
                      'reusedRuntime',
                    ])
                      if (metrics[key] is int) key: metrics[key],
                  });
                }
              }
              return event;
            }),
        alignmentProvider: const AttentionAlignmentProvider(enabled: true),
        onPublished: (key, request, output, bundle) async {
          generated++;
          generatedMs += output.durationMs;
          record({
            "event": "published",
            "passage": request.start.passageId,
            "durationMs": output.durationMs,
          });
        },
      );
      final player = _ObservedPlayer(cache, record);
      AudioInterruptionPolicy? interruptions;
      final owner = PlaybackCoordinator(
        speech: speech,
        player: player,
        segmenter: SpeechSegmenter((text) async {
          final watch = Stopwatch()..start();
          final result = await speech.tokenCount(text);
          tokenCountCalls++;
          tokenCountMs += watch.elapsedMilliseconds;
          return result;
        }),
        prepareEngine: () => speech.loadBundle(catalog.bundle),
        requestAudioFocus: () => interruptions!.acquireFocus(),
        discardAudio: cache.retainForReplay,
        releaseAudioBatch: (_) => cache.trimReplay(),
        holdPreparedAudio: (key) async {
          final lease = await files.acquire('cache/audio/$key.wav');
          return lease.release;
        },
      );
      final handler = await AudioService.init<SystemAudioHandler>(
        builder: () => SystemAudioHandler(owner),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.ureader.prototype.playback',
          androidNotificationChannelName: 'Lecture audio',
          androidStopForegroundOnPause: true,
          androidResumeOnClick: false,
        ),
      );
      interruptions = await AudioInterruptionPolicy.attach(
        owner,
        await AudioSession.instance,
      );
      final finished = Completer<void>();
      final played = <String>{};
      final completedSegments = <String>{};
      final chaptersPlayed = <String>{};
      final sampleComplete = Completer<void>();
      final firstStarted = Completer<void>();
      InstalledBookAudioSource? installedBook;
      int? startupMs;
      var stalls = 0, highWater = 0;
      var started = false;
      var testStopping = false, unexpectedPauses = 0;
      int? playingSince;
      var activePlayingMs = 0;
      var lastState = PlaybackState.stopped;
      var passed = false;
      void observe() {
        final now = elapsed.elapsedMilliseconds;
        if (owner.state == PlaybackState.playing) {
          playingSince ??= now;
        } else if (playingSince != null) {
          activePlayingMs += now - playingSince!;
          playingSince = null;
        }
        if (started &&
            !testStopping &&
            owner.state == PlaybackState.paused &&
            lastState != owner.state) {
          unexpectedPauses++;
          if (!finished.isCompleted) {
            finished.completeError(
              StateError('Device test interrupted by an unexpected pause'),
            );
          }
        }
        highWater = highWater > owner.preparedSegments
            ? highWater
            : owner.preparedSegments;
        if (owner.state == PlaybackState.playing) {
          started = true;
          if (!firstStarted.isCompleted) firstStarted.complete();
          if (owner.targetLocator != null) {
            chaptersPlayed.add(owner.targetLocator!.chapterId);
          }
          startupMs ??= elapsed.elapsedMilliseconds;
          if (owner.playedLocator != null) {
            played.add(owner.playedLocator!.passageId);
          }
        }
        if (started &&
            owner.state == PlaybackState.preparing &&
            lastState != owner.state) {
          stalls++;
          if (!finished.isCompleted) {
            finished.completeError(
              StateError('Audio reserve exhausted during playback'),
            );
          }
        }
        if (lastState != owner.state) {
          record({
            'event': 'state',
            'state': owner.state.name,
            'readySegments': owner.preparedSegments,
            'readyMs': owner.preparedAudioMs,
          });
        }
        lastState = owner.state;
        if (!finished.isCompleted && owner.state == PlaybackState.completed) {
          finished.complete();
        }
        if (!finished.isCompleted && owner.state == PlaybackState.error) {
          finished.completeError(
            StateError('Playback failed: ${owner.error?.code}'),
          );
        }
      }

      int? bufferingStart;
      var bufferingMs = 0, maxBufferingMs = 0;
      final clock = player.clockSamples.listen((sample) {
        clockSamples++;
        if (!started) return;
        if (sample.state == PlayerClockState.buffering) {
          bufferingStart ??= sample.monotonicMicros;
        } else if (bufferingStart != null) {
          final duration = (sample.monotonicMicros - bufferingStart!) ~/ 1000;
          bufferingMs += duration;
          if (duration > maxBufferingMs) maxBufferingMs = duration;
          bufferingStart = null;
        }
      });
      final transport = player.events.listen((event) {
        if (event.kind == PlayerEventKind.completed) {
          completedSegments.add(event.token.sessionId);
          if (completedSegments.length >= passageCount &&
              !sampleComplete.isCompleted) {
            sampleComplete.complete();
          }
        }
        final nextIndex = int.parse(event.token.sessionId.split('-').last) + 1;
        final next = SessionToken(
          'reader-player-$nextIndex',
          event.token.generation,
        );
        record({
          'event': event.kind.name,
          'token': event.token.sessionId,
          'nextQueued': player.contains(next),
          'nextCurrent': player.isCurrent(next),
          'readySegments': owner.preparedSegments,
          'readyMs': owner.preparedAudioMs,
        });
      });
      owner.addListener(observe);
      var progressWrites = Future<void>.value();
      final progressFile = File('${root.path}/progress.json');
      final progressTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        final progress = jsonEncode({
          'elapsedMs': elapsed.elapsedMilliseconds,
          'startupMs': startupMs,
          'state': owner.state.name,
          'completedSegments': completedSegments.length,
          'chaptersPlayed': chaptersPlayed.length,
          'readyMs': owner.preparedAudioMs,
          'readySegments': owner.preparedSegments,
          'playlistOpens': player.opens,
          'stalls': stalls,
        });
        progressWrites = progressWrites.then((_) async {
          await progressFile.writeAsString(progress);
        });
      });
      const corpus = [
        'Chaque matin, Léa ouvre la petite porte du jardin.',
        'À Noël, Émilie prépare une crème brûlée.',
        'Le chat regarde les oiseaux. Puis il retourne dans la maison.',
      ];
      try {
        if (bookQuery.isNotEmpty) {
          installedBook = await InstalledBookAudioSource.open(
            support: support,
            run: root,
            query: bookQuery,
          );
          await owner.playBook(
            BookSpeechContext(installedBook.book.key, installedBook.content),
            from: startAtChapterTail
                ? await installedBook.chapterTailLocator()
                : await installedBook.firstSpeechLocator(),
            exactFrom: startAtChapterTail,
          );
          if (testSeconds > 0) {
            await Future.any([firstStarted.future, finished.future])
                .timeout(const Duration(minutes: 2));
            if (!firstStarted.isCompleted) {
              throw StateError('Book ended before first playback');
            }
            await Future.any([
              Future<void>.delayed(Duration(seconds: testSeconds)),
              finished.future.then(
                (_) => throw StateError(
                  'Book ended before the requested test duration',
                ),
              ),
            ]);
          } else {
            await Future.any([sampleComplete.future, finished.future])
                .timeout(const Duration(minutes: 8));
            expect(
              completedSegments.length,
              greaterThanOrEqualTo(passageCount),
            );
          }
          testStopping = true;
          await owner.pause();
          if (testSeconds > 0) {
            expect(
              activePlayingMs,
              greaterThanOrEqualTo(testSeconds * 1000 - 500),
            );
          }
          if (startAtChapterTail) {
            expect(chaptersPlayed.length, greaterThanOrEqualTo(2));
          }
        } else {
          await owner.play(
            DemoText(
              id: 'continuous-validation',
              corpusVersion: 1,
              title: 'Lecture continue synthétique',
              passages: [
                for (var i = 0; i < passageCount; i++)
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
          expect(played.length, passageCount);
        }
        expect(generated, greaterThanOrEqualTo(passageCount));
        expect(
          player.opens,
          1,
          reason:
              'A reopened playlist indicates starvation or a broken transition',
        );
        expect(stalls, 0);
        expect(unexpectedPauses, 0);
        expect(clockSamples, greaterThan(0));
        expect(
          maxBufferingMs,
          lessThan(250),
          reason: "A native buffering episode exceeded 250 ms",
        );
        passed = true;
      } finally {
        progressTimer.cancel();
        await progressWrites;
        binding.reportData = {
          'status': passed ? 'passed' : 'failed',
          'requestedPassages': passageCount,
          'trace': trace,
          'passagesPlayed': played.length,
          'completedSegments': completedSegments.length,
          'chaptersPlayed': chaptersPlayed.length,
          'requestedPlaybackSeconds': testSeconds,
          'source': bookQuery.isEmpty ? 'synthetic' : 'installed-book',
          'catalogueDatabaseCloned': bookQuery.isNotEmpty,
          'startedAtChapterTail': startAtChapterTail,
          'userPositionsWritten': false,
          'publishedSegments': generated,
          'tokenCountCalls': tokenCountCalls,
          'tokenCountMs': tokenCountMs,
          'audioMs': generatedMs,
          'startupMs': startupMs,
          'elapsedMs': elapsed.elapsedMilliseconds,
          'playlistOpens': player.opens,
          'preparingTransitionsAfterStart': stalls,
          'unexpectedPauses': unexpectedPauses,
          'activePlayingMs':
              activePlayingMs +
              (playingSince == null
                  ? 0
                  : elapsed.elapsedMilliseconds - playingSince!),
          'clockSamples': clockSamples,
          'nativeBufferingMs': bufferingMs,
          'maxNativeBufferingMs': maxBufferingMs,
          'preparedSegmentHighWater': highWater,
          'productDatabaseOpened': false,
          'productAudioFocusAndService': true,
          'g1': 'not_evaluated',
          'audibleBoundaryQuality': 'not_evaluated',
        };
        owner.removeListener(observe);
        await transport.cancel();
        await clock.cancel();
        await interruptions.close();
        await handler.close();
        await owner.close();
        await installedBook?.close();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 27)));
}
