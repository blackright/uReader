import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/features/demo_reader/corpus_repository.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';
import 'package:prototype/infrastructure/audio/local_segment_player.dart';
import 'package:prototype/infrastructure/files/audio_cache.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';
import 'package:prototype/infrastructure/speech/platform_speech_engine.dart';

class ObservedSpeech implements SpeechEngine {
  ObservedSpeech(this.inner);
  final PlatformSpeechEngine inner;
  final outputs = <String, SpeechOutput>{};
  int requests = 0;
  @override
  Stream<SpeechEvent> get events => inner.events.map((event) {
    if (event.output != null) {
      outputs[event.output!.audioHandle] = event.output!;
    }
    return event;
  });
  @override
  Future<SpeechCapabilities> capabilities() => inner.capabilities();
  @override
  Future<void> loadBundle(BundleDescriptor bundle) => inner.loadBundle(bundle);
  @override
  Future<void> synthesize(SpeechRequest request) {
    requests++;
    return inner.synthesize(request);
  }

  @override
  Future<void> cancel(SessionToken token) => inner.cancel(token);
  @override
  Future<void> dispose() => inner.dispose();
}

class CapturedPlayer implements AudioPlayer {
  CapturedPlayer(this.cache, this.speech, this.directory)
    : inner = LocalSegmentPlayer(cache);
  final AudioCache cache;
  final ObservedSpeech speech;
  final Directory directory;
  final LocalSegmentPlayer inner;
  List<Map<String, Object?>>? capture;
  String? bookId;
  int opens = 0;
  final openedTexts = <String>[];
  @override
  Stream<PlayerEvent> get events => inner.events;
  @override
  Future<void> open(String handle, SessionToken token) async {
    final output = speech.outputs[handle]!;
    opens++;
    openedTexts.add(output.start.textId);
    final records = capture;
    if (records != null) {
      final bytes = await (await cache.files.audioCacheFile(handle))
          .readAsBytes();
      final name = '$bookId-s${records.length.toString().padLeft(3, '0')}.wav';
      final target = File('${directory.path}/$name');
      if (await target.exists()) {
        throw StateError('New capture directory required');
      }
      await target.writeAsBytes(bytes, flush: true);
      records.add({
        'file': name,
        'sha256': sha256.convert(bytes).toString(),
        'byteSize': bytes.length,
        'durationMs': output.durationMs,
        'passageId': output.start.passageId,
        'sourceStartUtf16': output.start.offsetUtf16,
        'sourceEndUtf16': output.end.offsetUtf16,
      });
    }
    await inner.open(handle, token);
  }

  @override
  Future<void> play() => inner.play();
  @override
  Future<void> pause() => inner.pause();
  @override
  Future<void> stop() => inner.stop();
  @override
  Future<void> dispose() => inner.dispose();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Dix textes complets et cinq répétitions des contrôles de phase 3',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Préparation de la recette…')),
        ),
      );
      await tester.pump();
      const bridge = MethodChannel('com.ureader.prototype/speech/v1');
      var attached = false;
      for (var attempt = 0; attempt < 50 && !attached; attempt++) {
        try {
          final result = await bridge.invokeMethod<Object?>('capabilities', {
            'protocolVersion': 1,
            'command': 'capabilities',
            'requestId': 'corpus-probe',
            'payload': <String, Object?>{},
          });
          attached = result is Map && result['protocolVersion'] == 1;
        } on MissingPluginException {
          /* Native activity may still be attaching. */
        }
        if (!attached) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
      }
      expect(
        attached,
        isTrue,
        reason: 'Native speech bridge must be attached before measurement',
      );
      final support = await getApplicationSupportDirectory();
      await support.create(recursive: true);
      final canonicalSupport = await support.resolveSymbolicLinks();
      final directory = Directory(
        '$canonicalSupport/ureader-corpus-validation-${DateTime.now().millisecondsSinceEpoch}',
      );
      await directory.create();
      final cache = AudioCache(
        await PrivateFileStore.open(Directory('${directory.path}/cache-root')),
      );
      final platform = PlatformSpeechEngine(cache);
      final speech = ObservedSpeech(platform);
      final player = CapturedPlayer(cache, speech, directory);
      final data = await rootBundle.load('assets/models/manifest.json');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final manifest = jsonDecode(utf8.decode(bytes)) as Map;
      final coordinator = PlaybackCoordinator(
        speech: speech,
        player: player,
        segmenter: SpeechSegmenter(platform.tokenCount),
        discardAudio: cache.remove,
        prepareEngine: () => speech.loadBundle(
          BundleDescriptor(
            id: manifest['bundleId'] as String,
            version: manifest['bundleVersion'] as String,
            manifestDigest: sha256.convert(bytes).toString(),
            files: [
              for (final entry in manifest['files'] as List)
                BundleFile(
                  relativePath: entry['relativePath'] as String,
                  byteSize: entry['byteSize'] as int,
                  sha256: entry['sha256'] as String,
                ),
            ],
          ),
        ),
      );
      const targeted = bool.fromEnvironment('UREADER_VALIDATION_TARGETED');
      final loaded = await CorpusRepository().load();
      final entries = targeted
          ? loaded.where((e) => ['fr-05', 'fr-06'].contains(e.text.id)).toList()
          : loaded;
      final cases = <Map<String, Object?>>[];
      final controls = <Map<String, Object?>>[];
      final progress = ValueNotifier<String>(
        'Préparation de la validation audio',
      );
      final report = <String, Object?>{
        'status': 'running',
        'cases': cases,
        'controls': controls,
        'manifestSha256': sha256.convert(bytes).toString(),
        'humanAudition': 'pending',
        'scope': targeted
            ? 'phase3_targeted_fr05_fr06_normalization_punctuation'
            : 'phase3_corpus_and_controls_only',
        'arbitraryPassageSeek': 'reserved_for_US4',
      };
      Future<void> persist() => File('${directory.path}/report.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
      Future<void> until(bool Function() predicate) async {
        final deadline = DateTime.now().add(const Duration(minutes: 8));
        while (!predicate()) {
          if (coordinator.state == PlaybackState.error) {
            throw StateError(coordinator.error!.code.name);
          }
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Validation timeout');
          }
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        await tester.pump();
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ValueListenableBuilder<String>(
                  valueListenable: progress,
                  builder: (_, value, _) => Text(value),
                ),
              ),
            ),
          ),
        );
        await persist();
        for (final entry in entries) {
          progress.value = 'Validation : ${entry.text.title}';
          await tester.pump();
          final captures = <Map<String, Object?>>[];
          player.capture = captures;
          player.bookId = entry.text.id;
          final clock = Stopwatch()..start();
          await coordinator.play(entry.text);
          await until(() => coordinator.state == PlaybackState.completed);
          clock.stop();
          var passageIndex = 0, cursor = 0;
          for (final record in captures) {
            final passage = entry.text.passages[passageIndex];
            expect(record['passageId'], passage.id);
            expect(record['sourceStartUtf16'], cursor);
            cursor = record['sourceEndUtf16'] as int;
            expect(cursor, lessThanOrEqualTo(passage.text.length));
            if (cursor == passage.text.length) {
              passageIndex++;
              cursor = 0;
            }
          }
          expect(passageIndex, entry.text.passages.length);
          expect(cursor, 0);
          cases.add({
            'id': entry.text.id,
            'title': entry.text.title,
            'status': 'mechanical_playback_completed',
            'sourceCoverageAndOrder': 'passed',
            'elapsedMs': clock.elapsedMilliseconds,
            'segments': captures,
            'humanAudition': 'pending',
          });
          player.capture = null;
          await coordinator.stop();
          await persist();
        }
        final short = entries.first.text;
        final other = entries[1].text;
        for (var i = 0; i < (targeted ? 0 : 5); i++) {
          progress.value = 'Commandes : série ${i + 1} sur 5';
          await tester.pump();
          await coordinator.play(short);
          await until(() => coordinator.state == PlaybackState.playing);
          await coordinator.pause();
          expect(coordinator.state, PlaybackState.paused);
          await coordinator.resume();
          await until(() => coordinator.state == PlaybackState.playing);
          await coordinator.stop();
          controls.add({
            'scenario': 'pause_resume',
            'iteration': i + 1,
            'status': 'passed',
          });
          await persist();

          await coordinator.play(short);
          expect(coordinator.state, PlaybackState.preparing);
          final opens = player.opens;
          await coordinator.stop();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 1)),
          );
          await tester.pump();
          expect(coordinator.state, PlaybackState.stopped);
          expect(player.opens, opens);
          controls.add({
            'scenario': 'stop_during_preparation',
            'iteration': i + 1,
            'status': 'passed',
          });
          await persist();

          await coordinator.play(short);
          final from = player.openedTexts.length;
          await coordinator.play(other);
          await until(() => coordinator.state == PlaybackState.playing);
          expect(
            player.openedTexts.sublist(from).every((id) => id == other.id),
            isTrue,
          );
          await coordinator.stop();
          controls.add({
            'scenario': 'change_text',
            'iteration': i + 1,
            'status': 'passed',
          });
          await persist();

          final before = player.opens;
          await Future.wait([
            coordinator.play(short),
            coordinator.play(short),
            coordinator.play(short),
          ]);
          await until(() => coordinator.state == PlaybackState.playing);
          expect(player.opens - before, 1);
          await coordinator.stop();
          controls.add({
            'scenario': 'repeated_play',
            'iteration': i + 1,
            'status': 'passed',
          });
          await persist();

          await coordinator.play(short);
          await until(() => coordinator.state == PlaybackState.playing);
          await coordinator.next();
          await until(() => coordinator.state == PlaybackState.playing);
          await coordinator.previous();
          await until(() => coordinator.state == PlaybackState.playing);
          expect(coordinator.playedLocator!.offsetUtf16, 0);
          await coordinator.stop();
          controls.add({
            'scenario': 'previous_next',
            'iteration': i + 1,
            'status': 'passed',
          });
          await persist();
        }
        expect(cases.length, targeted ? 2 : 10);
        expect(controls.length, targeted ? 0 : 25);
        report['status'] = 'mechanical_checks_passed_listening_pending';
        await persist();
      } catch (error) {
        report['status'] = 'incomplete';
        report['failureType'] = error.runtimeType.toString();
        await persist();
        rethrow;
      } finally {
        player.capture = null;
        await coordinator.close();
        await tester.pumpWidget(const SizedBox.shrink());
        progress.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
