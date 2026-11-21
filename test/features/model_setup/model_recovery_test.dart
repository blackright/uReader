import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/features/model_setup/model_installer.dart';
import 'package:prototype/features/model_setup/model_catalog.dart';
import 'package:prototype/features/model_setup/model_removal_service.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/diagnostics/safe_diagnostics.dart';
import 'package:prototype/infrastructure/files/operation_reconciler.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';

import 'model_installer_test.dart' show fixtureCatalog, MemoryBundleSource;

class InterruptedProcess extends Error {}

void main() {
  // All fixtures are tiny protocol resources, never evidence of vocal capability.
  late Directory root;
  late PrivateFileStore files;
  late PrototypeDatabase db;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ureader-install-recovery-');
    files = await PrivateFileStore.open(root);
    db = PrototypeDatabase(NativeDatabase.memory());
    await db.initialize();
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  for (final afterRename in [false, true]) {
    test(
      'interruption ${afterRename ? 'after' : 'before'} publication recovers verified version',
      () async {
        final catalog = fixtureCatalog([1, 2, 3]);
        Future<void> crash() async {
          throw InterruptedProcess();
        }

        final installer = ModelInstaller(
          catalog: catalog,
          files: files,
          database: db,
          source: MemoryBundleSource([1, 2, 3]),
          beforePublication: afterRename ? null : crash,
          afterPublication: afterRename ? crash : null,
        );
        await expectLater(
          installer.install(),
          throwsA(isA<InterruptedProcess>()),
        );
        expect(await db.isBundleReady(catalog.bundle), isFalse);
        final summary = await OperationReconciler(
          journal: db,
          files: files,
          resolveTrustedBundle: catalog.resolve,
          diagnostics: SafeDiagnostics(clock: SystemClock()),
        ).reconcile();
        expect(summary.completed, 1);
        expect(await db.isBundleReady(catalog.bundle), isTrue);
      },
    );
  }
  test('cancelled reinstall preserves prior ready version', () async {
    final catalog = fixtureCatalog([1, 2, 3]);
    final source = MemoryBundleSource([1, 2, 3]);
    final installer = ModelInstaller(
      catalog: catalog,
      files: files,
      database: db,
      source: source,
    );
    await installer.install();
    source.selected = false;
    await installer.install();
    expect(installer.error?.code, ErrorCode.cancelled);
    expect(await db.isBundleReady(catalog.bundle), isTrue);
    expect(
      await files.verify(catalog.bundle.directory, catalog.bundle.files),
      isTrue,
    );
  });
  test(
    'insufficient space for a new version preserves previous ready bytes',
    () async {
      final catalog = fixtureCatalog([1, 2, 3]);
      final old = ModelInstaller(
        catalog: catalog,
        files: files,
        database: db,
        source: MemoryBundleSource([1, 2, 3]),
      );
      await old.install();
      final metadata = jsonDecode(
        utf8.decode(catalog.embeddedBytes),
      ) as Map<String, dynamic>;
      metadata['bundleVersion'] = '2';
      final next = ModelCatalog.fromBytes(utf8.encode(jsonEncode(metadata)));
      final update = ModelInstaller(
        catalog: next,
        files: files,
        database: db,
        source: MemoryBundleSource([1, 2, 3]),
        hasSpace: (_) async => false,
      );
      await update.install();
      expect(await db.isBundleReady(catalog.bundle), isTrue);
      expect(
        await files.verify(catalog.bundle.directory, catalog.bundle.files),
        isTrue,
      );
      expect(await db.isBundleReady(next.bundle), isFalse);
    },
  );
  test(
    'removal waits for worker release and refuses competing install',
    () async {
      final catalog = fixtureCatalog([1, 2, 3]);
      final installer = ModelInstaller(
        catalog: catalog,
        files: files,
        database: db,
        source: MemoryBundleSource([1, 2, 3]),
      );
      await installer.install();
      final release = Completer<void>();
      final removal = ModelRemovalService(
        files: files,
        database: db,
        gate: installer.gate,
        releaseVoice: () => release.future,
        resumeVoice: () {},
      );
      final removing = removal.remove(catalog.bundle);
      await installer.install();
      expect(installer.error?.code, ErrorCode.resourceInUse);
      expect(await files.exists(catalog.bundle.directory), isTrue);
      release.complete();
      await removing;
      expect(await files.exists(catalog.bundle.directory), isFalse);
      expect(await db.isBundleReady(catalog.bundle), isFalse);
    },
  );
  test('failed worker release never deletes a ready model', () async {
    final catalog = fixtureCatalog([1, 2, 3]);
    final installer = ModelInstaller(
      catalog: catalog,
      files: files,
      database: db,
      source: MemoryBundleSource([1, 2, 3]),
    );
    await installer.install();
    final removal = ModelRemovalService(
      files: files,
      database: db,
      releaseVoice: () async {
        throw const AppError(ErrorCode.resourceInUse);
      },
      resumeVoice: () {},
    );
    await expectLater(removal.remove(catalog.bundle), throwsA(isA<AppError>()));
    expect(await db.isBundleReady(catalog.bundle), isTrue);
  });
  test(
    'removal clears stale installation so recovery cannot resurrect it',
    () async {
      final catalog = fixtureCatalog([1, 2, 3]);
      final installer = ModelInstaller(
        catalog: catalog,
        files: files,
        database: db,
        source: MemoryBundleSource([1, 2, 3]),
        afterPublication: () async {
          throw InterruptedProcess();
        },
      );
      await expectLater(
        installer.install(),
        throwsA(isA<InterruptedProcess>()),
      );
      expect(await db.pendingOperations(), isNotEmpty);
      final removal = ModelRemovalService(
        files: files,
        database: db,
        releaseVoice: () async {},
        resumeVoice: () {},
      );
      await removal.remove(catalog.bundle);
      await OperationReconciler(
        journal: db,
        files: files,
        resolveTrustedBundle: catalog.resolve,
        diagnostics: SafeDiagnostics(clock: SystemClock()),
      ).reconcile();
      expect(await db.isBundleReady(catalog.bundle), isFalse);
      expect(await files.exists(catalog.bundle.directory), isFalse);
      expect(await db.pendingOperations(), isEmpty);
    },
  );
}
