// Run only AFTER the projection/ZIP gates permit a real product-schema upgrade.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:prototype/app/dependencies.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/model_setup/model_catalog.dart';
import 'package:prototype/infrastructure/epub/epub_projection_worker.dart';
import 'package:prototype/infrastructure/epub/image_policy.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';

import 'epub_gate_jpeg.dart';
import 'epub_gate_resources.dart';
import 'feasibility_bootstrap.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'foundation gates, additive real upgrade and installed voice continuity',
    (tester) async {
      await waitForNative(tester);
      final report = <String, Object?>{};
      await tester.runAsync(() async {
        final rss = <int>[ProcessInfo.currentRss];
        final clock = Stopwatch()..start();
        for (final entry in gateFragments.entries) {
          final result = await EpubProjectionWorker.projectString(
            key: ContentKey(ContentKind.book, entry.key, 1),
            chapterOrdinal: 0,
            xhtml: entry.value,
            localStyles: ['.hidden {display:none}'],
          );
          expect(result.blocks, isNotEmpty);
          expect(result.blocks.every((b) => b.text.length <= 8192), true);
          expect(result.anchors.containsKey('passage'), true);
          rss.add(ProcessInfo.currentRss);
        }
        report['projectionResources'] = gateFragments.length;
        report['projectionElapsedMs'] = clock.elapsedMilliseconds;
        report['rssBytesBeforeAfterEachResource'] = rss;
        report['rssIsPeakMeasurement'] = false;
        for (final data in [
          base64Decode(gatePngBase64),
          base64Decode(gateJpegBase64),
        ]) {
          expect(ImagePolicy.inspect(data).usable, true);
          final codec = await ui.instantiateImageCodec(data);
          try {
            final frame = await codec.getNextFrame();
            expect(frame.image.width, 2);
            expect(frame.image.height, 2);
            frame.image.dispose();
          } finally {
            codec.dispose();
          }
        }
        report['pngAndJpegDecodedOnAndroid'] = true;
        final support = await (await getApplicationSupportDirectory())
            .resolveSymbolicLinks();
        final labId =
            'ureader-epub-foundations-${DateTime.now().microsecondsSinceEpoch}';
        final laboratory = Directory(p.join(support, labId));
        expect(await laboratory.exists(), false);
        await laboratory.create();
        try {
          final storeRoot = Directory(p.join(laboratory.path, 'store'));
          final store = await BookFileStore.open(storeRoot);
          await store.writeStaged(
            'op',
            'source',
            Stream.value([1, 2, 3]),
            maxBytes: 3,
          );
          await store.publish('op', 'b1');
          final lease = await store.acquire('b1');
          await expectLater(
            store.removeBook('b1'),
            throwsA(
              isA<AppError>().having(
                (e) => e.code,
                'code',
                ErrorCode.resourceInUse,
              ),
            ),
          );
          lease.release();
          await store.removeBook('b1');
          await Directory(p.join(storeRoot.path, 'books')).delete();
          final outside = await Directory(p.join(laboratory.path, 'outside'))
              .create();
          final link = Link(p.join(storeRoot.path, 'books'));
          await link.create(outside.path);
          await expectLater(
            store.bookFile('b1', 'r0'),
            throwsA(
              isA<AppError>().having(
                (e) => e.code,
                'code',
                ErrorCode.unsafePath,
              ),
            ),
          );
          await link.delete();
          expect(await outside.list().isEmpty, true);
          report['androidBookLeasesAndSymlinkRefusal'] = true;
        } finally {
          final checked = await laboratory.resolveSymbolicLinks();
          expect(
            p.isWithin(support, checked) && p.basename(checked) == labId,
            true,
          );
          await Directory(checked).delete(recursive: true);
        }
        final beforeFile = File(
          p.join(support, 'ureader-prototype', 'prototype.sqlite'),
        );
        final header = await beforeFile
            .openRead(0, 100)
            .fold<List<int>>([], (bytes, part) => bytes..addAll(part));
        expect(header.length, 100);
        expect(String.fromCharCodes(header.take(16)), 'SQLite format 3\u0000');
        report['schemaBeforeUpgrade'] = ByteData.sublistView(
          Uint8List.fromList(header),
        ).getUint32(60);
      });
      final dependencies = (await tester.runAsync(
        () => AppDependencies.open(),
      ))!;
      final owner = dependencies.playback;
      final probeId =
          'epub-phase2-probe-${DateTime.now().microsecondsSinceEpoch}';
      addTearDown(() async {
        try {
          await owner?.stop();
          await dependencies.database.customStatement(
            'DELETE FROM positions WHERE text_id=?',
            [probeId],
          );
        } finally {
          await dependencies.dispose();
        }
      });
      final positionsBefore = await tester.runAsync(
        () async => jsonEncode(
          (await dependencies.database
                  .customSelect('SELECT * FROM positions ORDER BY text_id,mode')
                  .get())
              .map((row) => row.data)
              .toList(),
        ),
      );
      final manifest = await rootBundle.load('assets/models/manifest.json');
      final catalog = ModelCatalog.fromBytes(
        manifest.buffer.asUint8List(
          manifest.offsetInBytes,
          manifest.lengthInBytes,
        ),
      );
      expect(
        await tester.runAsync(
          () => dependencies.database.isBundleReady(catalog.bundle),
        ),
        true,
      );
      expect(owner, isNotNull);
      expect(owner!.state, PlaybackState.stopped);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Validation de continuité vocale…')),
        ),
      );
      final text = DemoText(
        id: probeId,
        corpusVersion: 1,
        title: 'Essai synthétique de mise à niveau',
        passages: [
          Passage(
            id: 'p0',
            textId: probeId,
            ordinal: 0,
            text: 'Chaque matin, Léa ouvre la petite porte du jardin.',
          ),
        ],
      );
      await tester.runAsync(() => owner.play(text));
      var started = false;
      for (var attempt = 0; attempt < 600; attempt++) {
        expect(
          owner.state,
          isNot(PlaybackState.error),
          reason: owner.error?.message,
        );
        if (owner.state == PlaybackState.playing &&
            owner.durableLocator != null) {
          started = true;
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(started, true);
      await tester.runAsync(() => dependencies.systemAudio!.stop());
      await tester.runAsync(
        () => dependencies.database.customStatement(
          'DELETE FROM positions WHERE text_id=?',
          [probeId],
        ),
      );
      final positionsAfter = await tester.runAsync(
        () async => jsonEncode(
          (await dependencies.database
                  .customSelect('SELECT * FROM positions ORDER BY text_id,mode')
                  .get())
              .map((row) => row.data)
              .toList(),
        ),
      );
      expect(positionsAfter == positionsBefore, true);
      final schemaAfter = await tester.runAsync(
        () async =>
            (await dependencies.database
                    .customSelect('PRAGMA user_version')
                    .getSingle())
                .data
                .values
                .single,
      );
      expect(schemaAfter, 2);
      report.addAll({
        'schemaAfterUpgrade': schemaAfter,
        'installedVoiceReady': true,
        'realPlayerStarted': started,
        'userPositionsUnchangedDuringPlaybackProbe': true,
        'beforeUpgradeBackupComparison': 'requires separate host verification',
        'syntheticProbePositionRemoved': true,
        'firstAudibleSoundMeasured': false,
        'otherLanguagesValidated': false,
      });
      binding.reportData = report;
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
