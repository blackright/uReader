import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';

void main() {
  late Directory root;
  late BookFileStore books;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('epub-files-');
    books = await BookFileStore.open(root);
  });
  tearDown(() => root.delete(recursive: true));
  test(
    'generated namespaces, atomic publication, no overwrite or model deletion',
    () async {
      await books.writeStaged(
        'op1',
        'source',
        Stream.value([1, 2, 3]),
        maxBytes: 3,
      );
      await books.publish('op1', 'b1');
      expect(await (await books.bookFile('b1', 'source')).readAsBytes(), [
        1,
        2,
        3,
      ]);
      await books.writeStaged('op2', 'source', Stream.value([4]), maxBytes: 1);
      await expectLater(books.publish('op2', 'b1'), throwsA(isA<AppError>()));
      await expectLater(
        books.removeBook('../models'),
        throwsA(isA<AppError>()),
      );
    },
  );
  test('lease blocks deletion and release is idempotent', () async {
    await books.writeStaged('op', 'r0', Stream.value([1]), maxBytes: 1);
    await books.publish('op', 'b1');
    final lease = await books.acquire('b1');
    await expectLater(books.removeBook('b1'), throwsA(isA<AppError>()));
    lease.release();
    lease.release();
    await books.removeBook('b1');
    expect(await Directory('${root.path}/books/b1').exists(), false);
  });
  test('long copy does not hold the model/audio serialization queue', () async {
    final source = StreamController<List<int>>();
    final copying = books.writeStaged(
      'op',
      'source',
      source.stream,
      maxBytes: 100,
    );
    source.add([1]);
    final files = await PrivateFileStore.open(root);
    await files
        .writeAudioCache('a' * 64, [1, 2, 3])
        .timeout(const Duration(seconds: 2));
    await source.close();
    await copying;
  });
  test('cancelled/oversized streams leave no published partial file', () async {
    await expectLater(
      books.writeStaged('op', 'source', Stream.value([1, 2]), maxBytes: 1),
      throwsA(isA<AppError>()),
    );
    expect(await File('${root.path}/book-staging/op/source').exists(), false);
    expect(
      await File('${root.path}/book-staging/op/source.part').exists(),
      false,
    );
    await expectLater(
      books.writeStaged(
        'cancelled',
        'r0',
        Stream.value([1]),
        maxBytes: 10,
        cancelled: () => true,
      ),
      throwsA(isA<AppError>()),
    );
  });
  test('symlinked book subtree is refused', () async {
    final outside = await Directory.systemTemp.createTemp('epub-outside-');
    addTearDown(() => outside.delete(recursive: true));
    try {
      await Link('${root.path}/books').create(outside.path);
    } on FileSystemException {
      markTestSkipped('Création de lien non autorisée sur cet hôte');
      return;
    }
    await expectLater(books.bookFile('b1', 'r0'), throwsA(isA<AppError>()));
    await Link('${root.path}/books').delete();
    expect(await outside.list().isEmpty, true);
  });
}
