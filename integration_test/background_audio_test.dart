import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/app/dependencies.dart';
import 'package:prototype/app/prototype_app.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';

import 'feasibility_bootstrap.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real voice, shared handler, UI reconstruction and manual resume',
    (tester) async {
      await waitForNative(tester);
      final deps = await tester.runAsync(() => AppDependencies.open());
      expect(deps, isNotNull);
      final app = deps!;
      addTearDown(app.dispose);
      final owner = app.playback!;
      final system = app.systemAudio!;
      expect(owner.state, PlaybackState.stopped);
      expect(system.owner, same(owner));
      await tester.pumpWidget(
        PrototypeApp(createDependencies: () async => app),
      );
      await tester.pump();
      final texts = await tester.runAsync(app.corpus.load);
      await tester.runAsync(() => owner.play(texts!.first.text));
      Future<void> waitPlaying() async {
        for (var i = 0; i < 600; i++) {
          if (owner.state == PlaybackState.playing) return;
          expect(
            owner.state,
            isNot(PlaybackState.error),
            reason: owner.error?.message,
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
        fail('No real player start in 60 seconds');
      }

      await waitPlaying();
      await tester.runAsync(system.pause);
      expect(owner.state, PlaybackState.paused);
      expect(system.playbackState.value.playing, isFalse);
      // Rebuild the UI with the same application-owned resources.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        PrototypeApp(createDependencies: () async => app),
      );
      await tester.pump();
      expect(app.playback, same(owner));
      expect(owner.state, PlaybackState.paused);
      await tester.runAsync(system.play);
      await waitPlaying();
      await tester.runAsync(system.stop);
      expect(owner.state, PlaybackState.stopped);
      expect(system.playbackState.value.playing, isFalse);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      expect(owner.state, PlaybackState.stopped);
      binding.reportData = {
        'sharedOwner': true,
        'realPlayerStarted': true,
        'manualResume': true,
        'uiReconstructionPaused': true,
        'stoppedWithoutLateRestart': true,
        'physicalCallsAndHeadphones': 'not_evaluated',
        'twentyMinutesLocked': 'not_evaluated',
      };
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
