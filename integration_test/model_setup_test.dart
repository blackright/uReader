import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/features/model_setup/model_installer.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/diagnostics/safe_diagnostics.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';
import 'package:prototype/infrastructure/files/operation_reconciler.dart';

import '../test/features/model_setup/model_installer_test.dart'
    show fixtureCatalog, MemoryBundleSource;
import 'feasibility_bootstrap.dart';

class InstallationInterrupted extends Error {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'local fixture faults and publication recovery on actual private storage',
    (tester) async {
      await waitForNative(tester);
      final support = await getApplicationSupportDirectory();
      final base = Directory(
        '${await support.resolveSymbolicLinks()}/ureader-model-setup-validation-${DateTime.now().millisecondsSinceEpoch}',
      );
      await base.create();
      final results = <String, Object?>{};
      for (final fault in [
        'missing',
        'cancel',
        'corrupt',
        'storage',
        'lost_source',
        'before_publish',
        'after_publish',
      ]) {
        final files = await PrivateFileStore.open(
          Directory('${base.path}/$fault'),
        );
        var db = PrototypeDatabase(NativeDatabase(await files.databaseFile()));
        await db.initialize();
        final source = MemoryBundleSource(
          fault == 'corrupt' ? [3, 2, 1] : [1, 2, 3],
        );
        final catalog = fixtureCatalog([1, 2, 3]);
        final installer = ModelInstaller(
          catalog: catalog,
          files: files,
          database: db,
          source: source,
          hasSpace: fault == 'storage' ? (_) async => false : null,
          beforePublication: fault == 'before_publish'
              ? () async {
                  throw InstallationInterrupted();
                }
              : null,
          afterPublication: fault == 'after_publish'
              ? () async {
                  throw InstallationInterrupted();
                }
              : null,
        );
        if (fault == 'missing') source.data.clear();
        if (fault == 'cancel') source.beforeRead = installer.cancel;
        if (fault == 'lost_source') {
          source.beforeRead = () async {
            throw const AppError(ErrorCode.modelMissing);
          };
        }
        try {
          await installer.install();
          expect(await db.isBundleReady(catalog.bundle), isFalse);
          expect(installer.state, ModelSetupState.error);
          results[fault] = {
            'ready': false,
            'error': installer.error?.code.name,
            'fixtureOnly': true,
          };
        } on InstallationInterrupted {
          await db.close();
          db = PrototypeDatabase(NativeDatabase(await files.databaseFile()));
          await db.initialize();
          final recovered = await OperationReconciler(
            journal: db,
            files: files,
            resolveTrustedBundle: catalog.resolve,
            diagnostics: SafeDiagnostics(clock: SystemClock()),
          ).reconcile();
          expect(recovered.completed, 1);
          expect(await db.isBundleReady(catalog.bundle), isTrue);
          results[fault] = {'recovered': true, 'fixtureOnly': true};
        } finally {
          await installer.close();
          await db.close();
        }
      }
      await File('${base.path}/report.json').writeAsString(
        jsonEncode({
          'scope': 'small_local_fixture_not_vocal_capability',
          'networkLoss': 'not_applicable_no_network_delivery',
          'results': results,
        }),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Contrôles locaux terminés')),
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
