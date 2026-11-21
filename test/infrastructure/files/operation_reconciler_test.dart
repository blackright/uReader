import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/diagnostics/safe_diagnostics.dart';
import 'package:prototype/infrastructure/files/operation_reconciler.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';

class SimulatedCrash extends Error {}

void main() {
  late Directory root;
  late PrivateFileStore files;
  late PrototypeDatabase db;
  late BundleDescriptor bundle;
  late JournalOperation operation;
  const bytes = [1, 2, 3];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ureader-recovery-');
    files = await PrivateFileStore.open(root);
    db = PrototypeDatabase(NativeDatabase(File('${root.path}/journal.sqlite')));
    await db.initialize();
    bundle = BundleDescriptor(
      id: 'french',
      version: 'v1',
      manifestDigest: 'a' * 64,
      files: [
        BundleFile(
          relativePath: 'model.bin',
          byteSize: 3,
          sha256: sha256.convert(bytes).toString(),
        ),
      ],
    );
    operation = JournalOperation(
      id: 'op1',
      kind: OperationKind.install,
      bundleId: bundle.id,
      bundleVersion: bundle.version,
      manifestDigest: bundle.manifestDigest,
    );
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  OperationReconciler recovery({
    Future<void> Function(RecoveryCheckpoint)? fault,
    bool trusted = true,
  }) => OperationReconciler(
    journal: db,
    files: files,
    resolveTrustedBundle: (id, version, digest) async =>
        trusted ? bundle : null,
    diagnostics: SafeDiagnostics(clock: SystemClock()),
    checkpoint: fault,
  );

  for (final point in RecoveryCheckpoint.values) {
    test('Reprise durable après interruption ${point.name}', () async {
      await db.saveOperation(operation);
      await files.writeStagedFile('op1', 'model.bin', bytes, maxBytes: 3);
      await expectLater(
        recovery(
          fault: (current) async {
            if (current == point) throw SimulatedCrash();
          },
        ).reconcile(),
        throwsA(isA<SimulatedCrash>()),
      );
      expect(
        await db.customSelect('SELECT * FROM installed_bundles').get(),
        isEmpty,
      );
      await db.close();
      db = PrototypeDatabase(
        NativeDatabase(File('${root.path}/journal.sqlite')),
      );
      final result = await recovery().reconcile();
      expect(result.completed, 1);
      expect(await db.pendingOperations(), isEmpty);
      expect(await files.verify(bundle.directory, bundle.files), isTrue);
      expect(
        (await db.customSelect('SELECT * FROM installed_bundles').get()).length,
        1,
      );
      expect((await recovery().reconcile()).completed, 0);
    });
  }
  test(
    'Copie incomplète nettoyée sans effacer une autre version prête',
    () async {
      await db.saveOperation(operation);
      await files.writeStagedFile('op1', 'model.bin', bytes, maxBytes: 3);
      await recovery().reconcile();
      final interrupted = JournalOperation(
        id: 'op2',
        kind: OperationKind.install,
        bundleId: 'french',
        bundleVersion: 'v2',
        manifestDigest: 'b' * 64,
      );
      final nextBundle = BundleDescriptor(
        id: 'french',
        version: 'v2',
        manifestDigest: 'b' * 64,
        files: bundle.files,
      );
      await db.saveOperation(interrupted);
      await files.writeStagedFile('op2', 'model.bin', [1], maxBytes: 3);
      final next = OperationReconciler(
        journal: db,
        files: files,
        resolveTrustedBundle: (_, _, _) async => nextBundle,
        diagnostics: SafeDiagnostics(clock: SystemClock()),
      );
      expect((await next.reconcile()).failed, 1);
      expect(await files.exists('staging/op2'), isFalse);
      expect(await files.verify(bundle.directory, bundle.files), isTrue);
      expect(
        (await db.customSelect('SELECT * FROM installed_bundles').get()).length,
        1,
      );
    },
  );
  test('Le journal seul ne suffit pas à activer un modèle', () async {
    await db.saveOperation(operation);
    await files.writeStagedFile('op1', 'model.bin', bytes, maxBytes: 3);
    expect((await recovery(trusted: false).reconcile()).failed, 1);
    expect(
      await db.customSelect('SELECT * FROM installed_bundles').get(),
      isEmpty,
    );
    expect(
      (await db.pendingOperations()).single.errorCode,
      ErrorCode.modelIntegrityFailed,
    );
  });
  test('Nettoie uniquement le staging orphelin, sans modèle publié', () async {
    await files.writeStagedFile('orphan', 'model.bin', bytes, maxBytes: 3);
    expect((await recovery().reconcile()).failed, 0);
    expect(await files.exists('staging/orphan'), isFalse);
    expect(
      await db.customSelect('SELECT * FROM installed_bundles').get(),
      isEmpty,
    );
  });
  test('Suppression active refusée puis rejouée après libération', () async {
    await db.saveOperation(operation);
    await files.writeStagedFile('op1', 'model.bin', bytes, maxBytes: 3);
    await recovery().reconcile();
    final lease = await files.acquire('models/french/v1/model.bin');
    await db.saveOperation(
      JournalOperation(
        id: 'delete1',
        kind: OperationKind.delete,
        bundleId: bundle.id,
        bundleVersion: bundle.version,
        manifestDigest: bundle.manifestDigest,
      ),
    );
    expect((await recovery().reconcile()).failed, 1);
    expect(await files.exists(bundle.directory), isTrue);
    expect(
      (await db.customSelect('SELECT * FROM installed_bundles').get()).length,
      1,
    );
    lease.release();
    expect((await recovery().reconcile()).completed, 1);
    expect(await files.exists(bundle.directory), isFalse);
    expect(
      await db.customSelect('SELECT * FROM installed_bundles').get(),
      isEmpty,
    );
  });
}
