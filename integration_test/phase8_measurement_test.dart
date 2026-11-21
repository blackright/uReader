import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/features/feasibility/measurement_collector.dart';
import 'package:prototype/features/listening/playback_coordinator.dart'
    as reader;
import 'package:prototype/features/listening/speech_segmenter.dart';
import 'package:prototype/features/model_setup/model_catalog.dart';
import 'package:prototype/infrastructure/audio/audio_interruption_policy.dart';
import 'package:prototype/infrastructure/audio/local_segment_player.dart';
import 'package:prototype/infrastructure/audio/system_audio_handler.dart';
import 'package:prototype/infrastructure/files/audio_cache.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';
import 'package:prototype/infrastructure/speech/platform_speech_engine.dart';

import 'feasibility_bootstrap.dart';

void emit(Map<String, Object?> value) {
  // Synthetic test identifiers and measurements only; never source text/paths.
  // ignore: avoid_print
  print('UREADER_PHASE8:${jsonEncode(value)}');
}

class Meter {
  final collector = MeasurementCollector();
  final watch = Stopwatch()..start();
  final requests = <String, MeasurementSample>{};
  final handles = <String, MeasurementSample>{};
  MeasurementSample? pending;
  final samples = <Map<String, Object?>>[];
  int? lastEnd;
  int syntheses = 0;
}

class MeteredSpeech extends PlatformSpeechEngine {
  MeteredSpeech(super.cache, this.meter);
  final Meter meter;
  @override
  Future<void> synthesize(SpeechRequest request) async {
    meter.syntheses++;
    meter.requests[request.requestId] =
        meter.pending ?? meter.collector.begin(TrialTemperature.warm);
    meter.pending = null;
    await super.synthesize(request);
  }

  @override
  Stream<SpeechEvent> get events => super.events.map((event) {
    final sample = meter.requests[event.requestId];
    if (event.output != null && sample != null) {
      meter.collector.markPcm(sample);
      meter.handles[event.output!.audioHandle] = sample;
    }
    if (event.kind == SpeechEventKind.failed) {
      emit({'kind': 'engine_failure', 'code': event.errorCode?.name});
    }
    return event;
  });
}

class MeteredPlayer extends LocalSegmentPlayer {
  MeteredPlayer(super.cache, this.meter);
  final Meter meter;
  MeasurementSample? current;
  @override
  Future<void> open(String audioHandle, SessionToken token) async {
    current = meter.handles[audioHandle];
    await super.open(audioHandle, token);
  }

  @override
  Stream<PlayerEvent> get events => super.events.map((event) {
    final sample = current;
    if (event.kind == PlayerEventKind.started &&
        sample != null &&
        sample.playerStarted == null) {
      meter.collector.markStarted(sample);
      final result = meter.collector.finish(sample);
      result['gapSincePreviousCompletionUs'] = meter.lastEnd == null
          ? null
          : meter.watch.elapsedMicroseconds - meter.lastEnd!;
      meter.samples.add(result);
      emit({'kind': 'sample', 'index': meter.samples.length, ...result});
    }
    if (event.kind == PlayerEventKind.completed) {
      meter.lastEnd = meter.watch.elapsedMicroseconds;
    }
    return event;
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('phase8 isolated profile measurement sequence', (tester) async {
    await waitForNative(tester);
    await tester.runAsync(() async {
      final support = await getApplicationSupportDirectory();
      final files = await PrivateFileStore.open(
        Directory(
          '${await support.resolveSymbolicLinks()}/ureader-phase8-benchmark',
        ),
      );
      final stateFile = File('${files.root.path}/sequence.json');
      final index = await stateFile.exists()
          ? (jsonDecode(await stateFile.readAsString()) as Map)['next'] as int
          : 0;
      if (index > 6) {
        emit({
          'kind': 'done',
          'mode': 'finished',
          'status': 'already_completed',
        });
        return;
      }
      final mode = index < 5
          ? 'cold'
          : index == 5
          ? 'warm'
          : 'duration';
      emit({
        'kind': 'begin',
        'mode': mode,
        'run': index + 1,
        'cache': 'isolated_benchmark_store_no_cache_lookup',
        'durationSeconds': mode == 'duration' ? 1200 : null,
      });
      final data = await rootBundle.load('assets/models/manifest.json');
      final catalog = ModelCatalog.fromBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final cache = AudioCache(files);
      final meter = Meter();
      final engine = MeteredSpeech(cache, meter);
      final player = MeteredPlayer(cache, meter);
      final session = await AudioSession.instance;
      AudioInterruptionPolicy? interruptions;
      final owner = reader.PlaybackCoordinator(
        speech: engine,
        player: player,
        segmenter: SpeechSegmenter(engine.tokenCount),
        prepareEngine: () => engine.loadBundle(catalog.bundle),
        discardAudio: cache.remove,
        requestAudioFocus: () => interruptions!.acquireFocus(),
      );
      final system = await AudioService.init<SystemAudioHandler>(
        builder: () => SystemAudioHandler(owner),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.ureader.prototype.phase8',
          androidNotificationChannelName: 'Mesure du prototype',
          androidStopForegroundOnPause: true,
          androidResumeOnClick: false,
        ),
      );
      interruptions = await AudioInterruptionPolicy.attach(owner, session);
      final focusObserver = session.interruptionEventStream.listen((event) {
        emit({
          'kind': 'audio_interruption',
          'begin': event.begin,
          'type': event.type.name,
        });
      });
      final noisyObserver = session.becomingNoisyEventStream.listen((_) {
        emit({'kind': 'output_became_noisy'});
      });
      DemoText text(int count) => DemoText(
        id: 'phase8-bench',
        corpusVersion: 1,
        title: 'Mesure locale',
        passages: List.generate(
          count,
          (i) => Passage(
            id: 'bench-p-$i',
            textId: 'phase8-bench',
            ordinal: i,
            text: 'Chaque matin, Léa ouvre la petite porte du jardin.',
          ),
        ),
      );
      Future<void> until(bool Function() ready, int seconds) async {
        final deadline = Stopwatch()..start();
        while (!ready()) {
          if (owner.state == reader.PlaybackState.error) {
            throw StateError('measurement_playback_failed');
          }
          if (deadline.elapsed.inSeconds >= seconds) {
            throw StateError('measurement_timeout');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      try {
        if (mode == 'warm') {
          await owner.play(text(1));
          await until(() => owner.state == reader.PlaybackState.playing, 90);
          await owner.stop();
          meter.samples.clear();
        }
        if (mode == 'duration') {
          meter.pending = meter.collector.begin(TrialTemperature.cold);
          await owner.play(text(400));
          await until(() => owner.state == reader.PlaybackState.playing, 180);
          emit({'kind': 'duration_started', 'seconds': 1200});
          final duration = Stopwatch()..start();
          while (duration.elapsed.inSeconds < 1200) {
            if (owner.state == reader.PlaybackState.error ||
                owner.state == reader.PlaybackState.completed ||
                owner.state == reader.PlaybackState.paused) {
              throw StateError('measurement_session_interrupted');
            }
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          emit({
            'kind': 'duration_finished',
            'elapsedMs': duration.elapsedMilliseconds,
          });
          await owner.stop();
        } else {
          for (var i = 0; i < (mode == 'cold' ? 1 : 5); i++) {
            meter.pending = meter.collector.begin(
              mode == 'cold' ? TrialTemperature.cold : TrialTemperature.warm,
            );
            await owner.play(text(1));
            await until(() => owner.state == reader.PlaybackState.playing, 90);
            await owner.stop();
          }
        }
        final result = {
          'kind': 'done',
          'mode': mode,
          'run': index + 1,
          'status': 'passed',
          'syntheses': meter.syntheses,
          'samples': meter.samples.length,
          'firstAudibleSoundUs': null,
          'pcmMeaning': 'completed_local_wav_available_to_application',
        };
        await File('${files.root.path}/result-${index + 1}.json').writeAsString(
          jsonEncode({...result, 'measurements': meter.samples}),
          flush: true,
        );
        await stateFile.writeAsString(
          jsonEncode({'next': index + 1}),
          flush: true,
        );
        emit(result);
      } catch (error) {
        emit({
          'kind': 'done',
          'mode': mode,
          'run': index + 1,
          'status': 'failed',
          'failureType': error.runtimeType.toString(),
          'ownerState': owner.state.name,
          'publicErrorCode': owner.error?.code.name,
        });
        rethrow;
      } finally {
        await focusObserver.cancel();
        await noisyObserver.cancel();
        await interruptions.close();
        await system.close();
        await owner.close();
      }
    });
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 30)));
}
