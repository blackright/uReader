import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/features/model_setup/bundle_reattestation.dart';
import 'package:prototype/features/model_setup/model_catalog.dart';
import 'package:prototype/features/model_setup/model_operation_gate.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';

class AfterVerifyFiles implements PrivateFiles {
  AfterVerifyFiles(this.delegate, this.after);
  final PrivateFiles delegate;
  final Future<void> Function() after;
  @override
  Future<bool> verify(String path, List<BundleFile> expected) async {
    final verified = await delegate.verify(path, expected);
    await after();
    return verified;
  }

  @override
  Future<bool> exists(String path) => delegate.exists(path);
  @override
  Future<List<String>> stagingDirectories() => delegate.stagingDirectories();
  @override
  Future<void> publish(String source, String destination) =>
      delegate.publish(source, destination);
  @override
  Future<void> delete(String path) => delegate.delete(path);
}

void main() {
  late Directory root;
  late PrivateFileStore files;
  late PrototypeDatabase db;
  late ModelCatalog catalog;
  final bytes = [1, 2, 3];
  setUp(() async {
    root = await Directory.systemTemp.createTemp('epub-reattest-');
    files = await PrivateFileStore.open(root);
    db = PrototypeDatabase(NativeDatabase.memory());
    await db.initialize();
    catalog = ModelCatalog.fromBytes(
      utf8.encode(
        jsonEncode({
          'schemaVersion': 1,
          'bundleId': 'fixture',
          'bundleVersion': '1',
          'language': 'fr',
          'engineProtocolVersion': 1,
          'deliveryMode': 'local_g0_derivation',
          'localInstallation': {'enabled': true},
          'activationGate': {'g0Verdict': 'passed'},
          'voice': {'language': 'fr'},
          'licenseNotices': [],
          'limits': {'maxBundleBytes': 3, 'maxDownloadBytes': 0},
          'files': [
            {
              'relativePath': 'fixture.bin',
              'byteSize': 3,
              'sha256': sha256.convert(bytes).toString(),
            },
          ],
        }),
      ),
    );
    await files.writeStagedStream(
      'seed',
      'fixture.bin',
      Stream.value(bytes),
      maxBytes: 3,
    );
    await files.publish('staging/seed', catalog.bundle.directory);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  Future<void> oldReady() => db.customStatement(
    "INSERT INTO installed_bundles VALUES ('fixture','1',?,'models/fixture/1','ready',1)",
    ['a' * 64],
  );
  Future<bool> run() => BundleReattestation(
    database: db,
    files: files,
    gate: ModelOperationGate(),
  ).run(catalog);
  test('updates only old ready after actual pin verification', () async {
    await oldReady();
    expect(await run(), true);
    expect(await db.isBundleReady(catalog.bundle), true);
  });
  test('does not activate orphan directory or corrupted weights', () async {
    expect(await run(), false);
    expect(await db.isBundleReady(catalog.bundle), false);
    await oldReady();
    await File('${root.path}/${catalog.bundle.directory}/fixture.bin')
        .writeAsBytes([9, 9, 9]);
    expect(await run(), false);
    expect(await db.isBundleReady(catalog.bundle), false);
  });
  test('pending deletion has priority and failed G0 cannot reattest', () async {
    await oldReady();
    await db.saveOperation(
      JournalOperation(
        id: 'delete1',
        kind: OperationKind.delete,
        bundleId: 'fixture',
        bundleVersion: '1',
        manifestDigest: 'a' * 64,
      ),
    );
    expect(await run(), false);
    expect(await db.isBundleReady(catalog.bundle), false);
    await db.forgetOperation('delete1');
    final map =
        jsonDecode(utf8.decode(catalog.embeddedBytes)) as Map<String, dynamic>;
    map['activationGate'] = {'g0Verdict': 'failed'};
    expect(
      await BundleReattestation(
        database: db,
        files: files,
        gate: ModelOperationGate(),
      ).run(ModelCatalog.fromBytes(utf8.encode(jsonEncode(map)))),
      false,
    );
  });
  test(
    'CAS refuses a stale digest and a deletion inserted during verification',
    () async {
      await oldReady();
      expect(
        await db.compareAndSwapBundleDigest(catalog.bundle, 'b' * 64),
        false,
      );
      await db.saveOperation(
        JournalOperation(
          id: 'delete1',
          kind: OperationKind.delete,
          bundleId: 'fixture',
          bundleVersion: '1',
          manifestDigest: 'a' * 64,
        ),
      );
      expect(
        await db.compareAndSwapBundleDigest(catalog.bundle, 'a' * 64),
        false,
      );
      expect(await db.isBundleReady(catalog.bundle), false);
    },
  );
  test(
    'deletion wins even when inserted after file verification began',
    () async {
      await oldReady();
      final gate = ModelOperationGate();
      final delayed = AfterVerifyFiles(files, () async {
        expect(gate.active, true);
        await db.saveOperation(
          JournalOperation(
            id: 'late-delete',
            kind: OperationKind.delete,
            bundleId: 'fixture',
            bundleVersion: '1',
            manifestDigest: 'a' * 64,
          ),
        );
      });
      expect(
        await BundleReattestation(
          database: db,
          files: delayed,
          gate: gate,
        ).run(catalog),
        false,
      );
      expect(await db.isBundleReady(catalog.bundle), false);
      expect(gate.active, false);
    },
  );
  test(
    'another manifest change during verification is not overwritten',
    () async {
      await oldReady();
      final delayed = AfterVerifyFiles(
        files,
        () => db.customStatement(
          'UPDATE installed_bundles SET manifest_digest=?',
          ['b' * 64],
        ),
      );
      expect(
        await BundleReattestation(
          database: db,
          files: delayed,
          gate: ModelOperationGate(),
        ).run(catalog),
        false,
      );
      expect(
        (await db
                .customSelect('SELECT manifest_digest FROM installed_bundles')
                .getSingle())
            .read<String>('manifest_digest'),
        'b' * 64,
      );
    },
  );
  test('a busy model gate never starts reattestation', () async {
    await oldReady();
    final gate = ModelOperationGate()..enter();
    expect(
      await BundleReattestation(
        database: db,
        files: files,
        gate: gate,
      ).run(catalog),
      false,
    );
    expect(gate.active, true);
    gate.leave();
  });
}
