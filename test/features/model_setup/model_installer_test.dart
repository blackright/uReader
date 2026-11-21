import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/features/model_setup/model_catalog.dart';
import 'package:prototype/features/model_setup/model_installer.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';

class MemoryBundleSource implements LocalBundleSource {
  MemoryBundleSource(this.data);
  final List<int> data;
  bool selected = true;
  int selections = 0;
  Future<void> Function()? beforeRead;
  @override
  Future<bool> chooseFolder() async {
    selections++;
    return selected;
  }

  @override
  Stream<List<int>> readFile(String name) async* {
    await beforeRead?.call();
    yield data;
  }

  @override
  Future<void> close() async {}
}

ModelCatalog fixtureCatalog(List<int> bytes) => ModelCatalog.fromBytes(
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
      'voice': {'id': 'fixture', 'language': 'fr'},
      'licenseNotices': ['Fixture only'],
      'limits': {'maxBundleBytes': bytes.length, 'maxDownloadBytes': 0},
      'files': [
        {
          'relativePath': 'fixture.bin',
          'byteSize': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        },
      ],
    }),
  ),
);
void main() {
  late Directory directory;
  late PrivateFileStore files;
  late PrototypeDatabase db;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ureader-setup-');
    files = await PrivateFileStore.open(directory);
    db = PrototypeDatabase(NativeDatabase.memory());
    await db.initialize();
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });
  test(
    'no copy until explicit action; verified publication becomes ready',
    () async {
      final source = MemoryBundleSource([1, 2, 3]);
      final catalog = fixtureCatalog([1, 2, 3]);
      final installer = ModelInstaller(
        catalog: catalog,
        files: files,
        database: db,
        source: source,
      );
      expect(source.selections, 0);
      await installer.install();
      expect(installer.state, ModelSetupState.ready);
      expect(
        await files.verify(catalog.bundle.directory, catalog.bundle.files),
        isTrue,
      );
      expect(await db.isBundleReady(catalog.bundle), isTrue);
      expect(await db.pendingOperations(), isEmpty);
    },
  );
  test('hash mismatch cannot activate a resource', () async {
    final installer = ModelInstaller(
      catalog: fixtureCatalog([1, 2, 3]),
      files: files,
      database: db,
      source: MemoryBundleSource([3, 2, 1]),
    );
    await installer.install();
    expect(installer.error?.code, ErrorCode.modelIntegrityFailed);
    expect(await db.isBundleReady(installer.catalog.bundle), isFalse);
  });
  test(
    'cancellation refuses late source bytes and leaves no ready row',
    () async {
      final source = MemoryBundleSource([1, 2, 3]);
      final installer = ModelInstaller(
        catalog: fixtureCatalog([1, 2, 3]),
        files: files,
        database: db,
        source: source,
      );
      source.beforeRead = installer.cancel;
      await installer.install();
      expect(installer.error?.code, ErrorCode.cancelled);
      expect(await db.isBundleReady(installer.catalog.bundle), isFalse);
    },
  );
  test('storage failure is explicit and text-independent', () async {
    final source = MemoryBundleSource([1, 2, 3]);
    final installer = ModelInstaller(
      catalog: fixtureCatalog([1, 2, 3]),
      files: files,
      database: db,
      source: source,
      hasSpace: (_) async => false,
    );
    await installer.install();
    expect(installer.state, ModelSetupState.error);
    expect(installer.error?.code, ErrorCode.storageUnavailable);
    expect(await db.pendingOperations(), isEmpty);
  });
}
