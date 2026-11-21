import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/ports.dart';
import 'package:prototype/features/listening/playback_controls.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';

import '../../fakes/fake_speech_engine.dart';

class SilentPlayer implements AudioPlayer {
  @override
  Stream<PlayerEvent> get events => const Stream.empty();
  @override
  Future<void> open(String handle, SessionToken token) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  for (final scale in [1.0, 3.2]) {
    testWidgets(
      'Commandes libellées et sans débordement, échelle simulée $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        final text = DemoText(
          id: 't',
          corpusVersion: 1,
          title: 'Essai',
          passages: [
            Passage(id: 'p', textId: 't', ordinal: 0, text: 'Bonjour.'),
          ],
        );
        final owner = PlaybackCoordinator(
          speech: FakeSpeechEngine(),
          player: SilentPlayer(),
          segmenter: SpeechSegmenter((s) async => s.length),
          prepareEngine: () async {},
          discardAudio: (_) async {},
        );
        try {
          await tester.runAsync(() => owner.play(text));
          expect(owner.textId, text.id);
          for (final state in [
            PlaybackState.stopped,
            PlaybackState.preparing,
            PlaybackState.playing,
            PlaybackState.paused,
            PlaybackState.completed,
            PlaybackState.error,
          ]) {
            owner.state = state;
            owner.error = const AppError(ErrorCode.modelMissing);
            await tester.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(
                    size: const Size(360, 800),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    body: SingleChildScrollView(
                      child: PlaybackControls(coordinator: owner, text: text),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(find.text('Écouter'), findsOneWidget);
            expect(find.text('Arrêter'), findsOneWidget);
            expect(
              find.text(state == PlaybackState.paused ? 'Reprendre' : 'Pause'),
              findsOneWidget,
            );
            expect(find.text('Précédent'), findsOneWidget);
            expect(find.text('Suivant'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
          await tester.runAsync(owner.close);
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
