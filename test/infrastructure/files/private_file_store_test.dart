import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';

void main() {
  late Directory root;
  late PrivateFileStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ureader-files-');
    store = await PrivateFileStore.open(root);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
    'Refuse chemins absolus, traversal, noms Windows et segments ambigus',
    () async {
      for (final name in [
        '../outside',
        '/absolute',
        'C:/outside',
        'a/../b',
        'a\\b',
        'CON',
        'a.',
        'a//b',
      ]) {
        await expectLater(store.exists(name), throwsA(isA<AppError>()));
      }
      expect(await store.exists('models/demo/v1'), isFalse);
    },
  );
  test('Publication vérifiée et protection par bail actif', () async {
    final bytes = [1, 2, 3];
    final specs = [
      BundleFile(
        relativePath: 'model.bin',
        byteSize: 3,
        sha256: sha256.convert(bytes).toString(),
      ),
    ];
    await store.writeStagedFile('op1', 'model.bin', bytes, maxBytes: 3);
    expect(await store.verify('staging/op1', specs), isTrue);
    await store.publish('staging/op1', 'models/demo/v1');
    final lease = await store.acquire('models/demo/v1/model.bin');
    await expectLater(store.delete('models/demo/v1'), throwsA(isA<AppError>()));
    lease.release();
    lease.release();
    await store.delete('models/demo/v1');
    await store.delete('models/demo/v1');
    expect(await store.exists('models/demo/v1'), isFalse);
    await expectLater(
      store.delete('prototype.sqlite'),
      throwsA(isA<AppError>()),
    );
    await expectLater(store.delete('models'), throwsA(isA<AppError>()));
  });
  test(
    'Refuse contenu altéré, fichiers supplémentaires et dépassement',
    () async {
      await store.writeStagedFile('op1', 'data.bin', [1], maxBytes: 1);
      final specs = [
        BundleFile(
          relativePath: 'data.bin',
          byteSize: 1,
          sha256: sha256.convert([2]).toString(),
        ),
      ];
      expect(await store.verify('staging/op1', specs), isFalse);
      await expectLater(
        store.writeStagedFile('op2', 'data.bin', [1, 2], maxBytes: 1),
        throwsA(isA<AppError>()),
      );
      expect(await store.exists('staging/op2/data.bin'), isFalse);
      await store.writeStagedFile('op1', 'extra.bin', [2], maxBytes: 1);
      expect(
        await store.verify('staging/op1', [
          BundleFile(
            relativePath: 'data.bin',
            byteSize: 1,
            sha256: sha256.convert([1]).toString(),
          ),
        ]),
        isFalse,
      );
    },
  );
  test('Refuse un lien symbolique sans toucher sa cible', () async {
    final outside = await Directory.systemTemp.createTemp('ureader-outside-');
    addTearDown(() => outside.delete(recursive: true));
    await File('${outside.path}/keep.txt').writeAsString('preserver');
    try {
      await Link('${root.path}/escape').create(outside.path);
    } on FileSystemException {
      markTestSkipped('Création de lien non autorisée sur cet hôte');
      return;
    }
    await expectLater(
      store.exists('escape/keep.txt'),
      throwsA(isA<AppError>()),
    );
    await expectLater(store.delete('escape'), throwsA(isA<AppError>()));
    expect(await File('${outside.path}/keep.txt').readAsString(), 'preserver');
    await Link('${root.path}/escape').delete();
    await Link('${root.path}/prototype.sqlite')
        .create('${outside.path}/keep.txt');
    await expectLater(store.databaseFile(), throwsA(isA<AppError>()));
    await Link('${root.path}/prototype.sqlite').delete();
  });
}
