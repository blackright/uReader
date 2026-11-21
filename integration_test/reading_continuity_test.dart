import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/app/dependencies.dart';
import 'package:prototype/app/prototype_app.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';

import 'feasibility_bootstrap.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'independent visual/audio positions, explicit seek and durable resume',
    (tester) async {
      await waitForNative(tester);
      final deps = (await tester.runAsync(() => AppDependencies.open()))!;
      final owner = deps.playback!;
      addTearDown(deps.dispose);
      final entries = (await tester.runAsync(deps.reader.load))!;
      final entry = entries.first;
      final target = Locator(
        textId: entry.text.id,
        corpusVersion: entry.text.corpusVersion,
        passageId: entry.text.passages[1].id,
        offsetUtf16: 0,
      );
      await tester.runAsync(() => deps.reader.selectText(entry));
      expect(owner.state, PlaybackState.stopped);
      await tester.pumpWidget(
        PrototypeApp(createDependencies: () async => deps),
      );
      await tester.pump();
      Future<void> waitPlaying() async {
        for (var i = 0; i < 600; i++) {
          if (owner.state == PlaybackState.playing &&
              owner.durableLocator != null) {
            return;
          }
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
        fail(
          'Real playback and durable checkpoint did not start in 60 seconds',
        );
      }

      await tester.runAsync(() => deps.reader.listenHere(target));
      await waitPlaying();
      await tester.runAsync(owner.pause);
      final heard = owner.playedLocator!;
      expect(heard.passageId, target.passageId);
      final before = await tester.runAsync(
        () => deps.positions.read(entry.text, ReadingMode.audio),
      );
      expect(before!.locator.passageId, target.passageId);
      await tester.runAsync(() => deps.reader.selectText(entries[1]));
      expect(owner.textId, entry.text.id);
      expect(owner.state, PlaybackState.paused);
      await tester.runAsync(deps.reader.showSpokenPassage);
      expect(deps.reader.visualLocator!.passageId, heard.passageId);
      final after = await tester.runAsync(
        () => deps.positions.read(entry.text, ReadingMode.audio),
      );
      expect(after!.revision, before.revision);
      await tester.runAsync(owner.stop);
      // Recreate the UI using the same application-owned services; never autoplay.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        PrototypeApp(createDependencies: () async => deps),
      );
      await tester.pump();
      expect(owner.state, PlaybackState.stopped);
      await tester.runAsync(deps.reader.listen);
      await waitPlaying();
      expect(owner.playedLocator!.passageId, target.passageId);
      await tester.runAsync(owner.stop);
      binding.reportData = {
        'realVoice': true,
        'explicitSecondParagraph': true,
        'visualDoesNotMoveAudio': true,
        'showSpokenDoesNotWriteAudio': true,
        'durableAudioCheckpoint': true,
        'uiReconstructionDoesNotPlay': true,
        'explicitResumeAtSavedParagraph': true,
        'fiveProcessRestarts': 'separate_protocol',
        'physicalTalkBack': 'not_evaluated',
      };
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
