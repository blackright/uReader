// Migration proof on a copy first, then the backed-up product DB. No new reader UI.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prototype/app/dependencies.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';

import 'feasibility_bootstrap.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'reader v3 migration preserves product and native installed voice',
    (tester) async {
      await waitForNative(tester);
      final support = await (await getApplicationSupportDirectory())
          .resolveSymbolicLinks();
      final root = Directory('$support/ureader-prototype');
      final lab = await Directory(
        '$support/reader-foundations-${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      final report = <String, Object?>{};
      await tester.runAsync(() async {
        for (final suffix in ['', '-wal', '-shm']) {
          final src = File('${root.path}/prototype.sqlite$suffix');
          if (await src.exists()) {
            await src.copy('${lab.path}/prototype.sqlite$suffix');
          }
        }
        final before = <String, String>{};
        final copy = PrototypeDatabase(
          NativeDatabase(
            File('${lab.path}/prototype.sqlite'),
            setup: (raw) {
              report['copySchemaBefore'] = raw
                  .select('PRAGMA user_version')
                  .single['user_version'];
              for (final row in raw.select(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
              )) {
                final table = row['name'] as String;
                final quoted = '"${table.replaceAll('"', '""')}"';
                final columns = raw.select('PRAGMA table_info($quoted)').length;
                final order = List.generate(
                  columns,
                  (i) => '${i + 1}',
                ).join(',');
                before[table] = jsonEncode(
                  raw
                      .select('SELECT * FROM $quoted ORDER BY $order')
                      .map((r) => Map<String, Object?>.from(r))
                      .toList(),
                );
              }
            },
          ),
        );
        try {
          await copy.initialize();
          expect(
            (await copy.customSelect('PRAGMA user_version').getSingle())
                .data
                .values
                .single,
            3,
          );
          for (final entry in before.entries) {
            final quoted = '"${entry.key.replaceAll('"', '""')}"';
            final columns =
                (await copy.customSelect('PRAGMA table_info($quoted)').get())
                    .length;
            final order = List.generate(columns, (i) => '${i + 1}').join(',');
            expect(
              jsonEncode(
                (await copy
                        .customSelect('SELECT * FROM $quoted ORDER BY $order')
                        .get())
                    .map((r) => r.data)
                    .toList(),
              ),
              entry.value,
            );
          }
          expect(
            await copy.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
          report['copyOldTablesUnchanged'] = before.length;
          report['copyMigrationPassed'] = true;
        } finally {
          await copy.close();
        }
      });
      final deps = (await tester.runAsync(() => AppDependencies.open()))!;
      final owner = deps.playback;
      final probe = 'reader-v3-probe-${DateTime.now().microsecondsSinceEpoch}';
      addTearDown(() async {
        try {
          await owner?.stop();
          await deps.database.customStatement(
            'DELETE FROM positions WHERE text_id=?',
            [probe],
          );
        } finally {
          await deps.dispose();
        }
      });
      expect(owner, isNotNull);
      expect(owner!.state, PlaybackState.stopped);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Validation des fondations du lecteur…')),
        ),
      );
      final positions = (await tester.runAsync(
        () async => jsonEncode(
          (await deps.database
                  .customSelect('SELECT * FROM positions ORDER BY text_id,mode')
                  .get())
              .map((r) => r.data)
              .toList(),
        ),
      ))!;
      final text = DemoText(
        id: probe,
        corpusVersion: 1,
        title: 'Essai synthétique',
        passages: [
          Passage(
            id: 'p0',
            textId: probe,
            ordinal: 0,
            text: 'Chaque matin, Léa ouvre la petite porte du jardin.',
          ),
        ],
      );
      await tester.runAsync(() => owner.play(text));
      var started = false;
      for (var i = 0; i < 600; i++) {
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
      await tester.runAsync(() async {
        await owner.stop();
        await deps.database.customStatement(
          'DELETE FROM positions WHERE text_id=?',
          [probe],
        );
        expect(
          jsonEncode(
            (await deps.database
                    .customSelect(
                      'SELECT * FROM positions ORDER BY text_id,mode',
                    )
                    .get())
                .map((r) => r.data)
                .toList(),
          ),
          positions,
        );
        expect(
          (await deps.database.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          3,
        );
        expect(
          await deps.database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        await deps.experiencePreferences.read();
      });
      report.addAll({
        'productSchemaAfter': 3,
        'realPlayerStarted': started,
        'nativeInstalledVoiceResolved': true,
        'probePositionRemoved': true,
        'historicalPositionsUnchangedDuringProbe': true,
        'audibleSampleMeasured': false,
        'newReaderUiImplemented': false,
      });
      binding.reportData = report;
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
