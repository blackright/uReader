import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/app/dependencies.dart';
import 'package:prototype/app/prototype_app.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/domain/app_error.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Lecture française locale, pause, reprise, arrêt et préparation annulée',
    (tester) async {
      var simulateMissing = true;
      final deps = await AppDependencies.open(
        loadSpeechManifest: () async {
          final data = await rootBundle.load('assets/models/manifest.json');
          if (!simulateMissing) return data;
          final manifest = jsonDecode(
            utf8.decode(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            ),
          ) as Map;
          manifest['bundleId'] = 'missing-test-bundle';
          return ByteData.sublistView(
            Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
          );
        },
      );
      final owner = deps.playback!;
      final states = <String>[];
      void record() => states.add(owner.state.name);
      owner.addListener(record);
      Future<void> until(
        bool Function() predicate, {
        bool allowError = false,
      }) async {
        final deadline = DateTime.now().add(const Duration(seconds: 120));
        while (!predicate()) {
          if (!allowError && owner.state == PlaybackState.error) {
            fail(owner.error!.message);
          }
          if (DateTime.now().isAfter(deadline)) {
            fail('Délai dépassé pendant la lecture locale.');
          }
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
        }
        await tester.pump();
      }

      try {
        final entries = await deps.corpus.load();
        await tester.pumpWidget(
          PrototypeApp(createDependencies: () async => deps),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(entries.first.text.title));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Écouter'));
        await until(() => owner.state == PlaybackState.error, allowError: true);
        expect(owner.error!.code, ErrorCode.modelMissing);
        expect(
          find.text(entries.first.text.passages.first.text),
          findsOneWidget,
        );
        simulateMissing = false;
        await tester.tap(find.text('Écouter'));
        await until(() => owner.state == PlaybackState.playing);
        expect(owner.playedLocator, isNotNull);
        await tester.tap(find.text('Pause'));
        await until(() => owner.state == PlaybackState.paused);
        await tester.tap(find.text('Reprendre'));
        await until(() => owner.state == PlaybackState.playing);
        await tester.tap(find.text('Arrêter'));
        await until(() => owner.state == PlaybackState.stopped);
        await tester.tap(find.text('Écouter'));
        await tester.pump();
        expect(owner.state, PlaybackState.preparing);
        await tester.tap(find.text('Arrêter'));
        await until(() => owner.state == PlaybackState.stopped);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 8)),
        );
        await tester.pump();
        expect(owner.state, PlaybackState.stopped);
        await tester.tap(find.text('Tous les textes'));
        await tester.pumpAndSettle();
        final numeric = entries.firstWhere(
          (e) => e.text.passages.any((p) => p.id == 'fr-05-p1'),
        );
        await tester.tap(find.text(numeric.text.title));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Écouter'));
        await until(() => owner.state == PlaybackState.playing);
        expect(owner.playedLocator!.textId, numeric.text.id);
        await tester.tap(find.text('Arrêter'));
        await until(() => owner.state == PlaybackState.stopped);
        await File('${deps.files.root.path}/offline-listening-result.json')
            .writeAsString(
              jsonEncode({
                'status': 'passed',
                'states': states,
                'realNativeSynthesisAndLocalPlayer': true,
                'untrustedBundleRejectedAndTextReadable': true,
                'pauseResumeStop': true,
                'stopDuringPreparationNoLatePlayback': true,
                'numericSourceRangeWithNormalizedSynthesis': true,
                'humanAuditionOfThisRun': false,
              }),
            );
      } finally {
        owner.removeListener(record);
        await tester.pumpWidget(const SizedBox.shrink());
        await deps.dispose();
      }
    },
  );
}
