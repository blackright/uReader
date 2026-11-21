import 'package:prototype/infrastructure/files/book_operation_reconciler.dart';
import 'package:prototype/infrastructure/database/book_operation_repository.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:prototype/features/library/book_importer.dart';
import 'package:prototype/infrastructure/epub/epub_import_source.dart';
import 'package:prototype/infrastructure/epub/epub_package_parser.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';

import '../../infrastructure/epub/epub_package_parser_test.dart' show fixture;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';

void main() {
  late PrototypeDatabase db;
  late BookRepository books;
  setUp(() {
    db = PrototypeDatabase(NativeDatabase.memory());
    books = BookRepository(db);
  });
  tearDown(() async {
    await db.close();
  });
  test('draft is invisible, source reservation is unique and losing operation is isolated', () async {
    await books.begin('op1', 'book1', 1);
    await books.begin('op2', 'book2', 1);
    expect(await books.readyPage(), isEmpty);
    expect(await books.reserve('op1', 'book1', 'a' * 64, 3), isNull);
    await expectLater(
      books.reserve('op2', 'book2', 'a' * 64, 3),
      throwsA(isA<BookFailure>()),
    );
    await books.abandon('op2', 'book2');
    expect(
      (await db.customSelect('SELECT book_id FROM books').get()).single
          .read<String>('book_id'),
      'book1',
    );
  });
  test(
    'cannot publish without validation and complete canonical data',
    () async {
      await books.begin('op', 'book', 1);
      await books.reserve('op', 'book', 'a' * 64, 1);
      await expectLater(
        books.commitReady('op', 'book', 'b' * 64),
        throwsA(isA<BookFailure>()),
      );
      expect(await books.readyPage(), isEmpty);
    },
  );
  test('literal search, pagination and unknown cursors are bounded', () async {
    await expectLater(books.readyPage(limit: 51), throwsA(isA<BookFailure>()));
    expect(await books.readyPage(search: '%_'), isEmpty);
  });
  test('successful publication exposes one ready book and detects identical reimport', () async {
    await books.begin('op', 'book', 1);
    await books.reserve('op', 'book', 'a' * 64, 3);
    final key = ContentKey(ContentKind.book, 'book', 1);
    await books.chapter(
      'op',
      BookChapter(
        key: key,
        id: 'c0',
        ordinal: 0,
        title: 'Chapter',
        resource: 'ch.xhtml',
        firstBlockOrdinal: 0,
        blockCount: 1,
        textUnits: 3,
      ),
    );
    await books.blocks(
      'op',
      [
        BookBlock(
          key: key,
          chapterId: 'c0',
          id: 'b0',
          ordinal: 0,
          kind: BookBlockKind.paragraph,
          text: 'ABC',
        ),
      ],
      firstOrdinal: 0,
      unitsBefore: 0,
    );
    await books.validated('op', 'book', 'b' * 64, '{}');
    await books.commitReady('op', 'book', 'b' * 64);
    expect((await books.readyPage()).single.key.id, 'book');
    await books.begin('op2', 'book2', 1);
    expect((await books.reserve('op2', 'book2', 'a' * 64, 3))!.key.id, 'book');
    await books.abandon('op2', 'book2');
    expect((await books.readyPage()).length, 1);
  });

  test('complete isolated import, identical bytes reimport and cancelled selection', () async {
    final dir = await Directory.systemTemp.createTemp('epub-import-');
    addTearDown(() => dir.delete(recursive: true));
    final files = await BookFileStore.open(dir);
    final source = ImportSource(files);
    final importer = BookImporter(
      source: source,
      books: books,
      files: files,
      normalizeKey: (s) async => s.toLowerCase(),
    );
    final states = <ImportStep>[];
    final first = await importer.importBook(
      'op',
      'book',
      1,
      progress: (p) => states.add(p.step),
    );
    expect(first.book!.languages, ['en']);
    expect(source.verified, true);
    expect(states, contains(ImportStep.finalizing));
    expect((await books.readyPage()).length, 1);
    final repeat = await importer.importBook('op2', 'book2', 1);
    expect(repeat.existing, true);
    expect(repeat.book!.key.id, 'book');
    source.selectCancelled = true;
    expect((await importer.importBook('op3', 'book3', 1)).cancelled, true);
    expect((await books.readyPage()).length, 1);
  });
  test('failure while verifying unused entry publishes nothing and preserves original', () async {
    final dir = await Directory.systemTemp.createTemp('epub-import-crc-');
    addTearDown(() => dir.delete(recursive: true));
    final files = await BookFileStore.open(dir);
    final source = ImportSource(files)..badUnused = true;
    final importer = BookImporter(
      source: source,
      books: books,
      files: files,
      normalizeKey: (s) async => s,
    );
    await expectLater(
      importer.importBook('op', 'book', 1),
      throwsA(isA<BookFailure>()),
    );
    expect(await books.readyPage(), isEmpty);
    expect(await (await files.stagingFile('op', 'source')).exists(), false);
    expect(source.original, [1, 2, 3]);
  });
  test(
    'simulated full disk aborts the draft with an actionable public error',
    () async {
      final dir = await Directory.systemTemp.createTemp('epub-full-');
      addTearDown(() => dir.delete(recursive: true));
      final files = await BookFileStore.open(dir);
      final source = ImportSource(files)
        ..copyFailure = const FileSystemException(
          'private input',
          'private path',
          OSError('disk full', 28),
        );
      final importer = BookImporter(
        source: source,
        books: books,
        files: files,
        normalizeKey: (s) async => s,
      );
      await expectLater(
        importer.importBook('op', 'book', 1),
        throwsA(
          isA<BookFailure>().having(
            (e) => e.code,
            'code',
            BookError.insufficientStorage,
          ),
        ),
      );
      expect(await books.readyPage(), isEmpty);
      expect(source.original, [1, 2, 3]);
    },
  );
  for (final checkpoint in [
    'before-validated',
    'validated',
    'renamed',
    'committed',
    'tampered',
  ]) {
    test(
      'recovers interrupted import at $checkpoint while preserving another ready book',
      () async {
        final dir = await Directory.systemTemp.createTemp('epub-checkpoint-');
        addTearDown(() => dir.delete(recursive: true));
        final files = await BookFileStore.open(dir);
        final stable = BookImporter(
          source: ImportSource(files),
          books: books,
          files: files,
          normalizeKey: (s) async => s,
        );
        await stable.importBook('other-op', 'other-book', 1);
        final faultBooks = FaultBooks(db, checkpoint, files);
        final source = ImportSource(files)..original.add(4);
        final importer = BookImporter(
          source: source,
          books: faultBooks,
          files: files,
          normalizeKey: (s) async => s,
        );
        await expectLater(
          importer.importBook('op', 'book', 1),
          throwsA(isA<BookFailure>()),
        );
        final reconciler = BookOperationReconciler(
          books,
          BookOperationRepository(db),
          files,
        );
        if (checkpoint == 'tampered') {
          final issues = await reconciler.recover();
          expect(issues.map((e) => e.code), contains(BookError.invalidContent));
        } else {
          await reconciler.recover();
          await reconciler.recover();
        }
        final ids = (await books.readyPage()).map((b) => b.key.id).toSet();
        expect(ids, contains('other-book'));
        expect(
          ids.contains('book'),
          !['before-validated', 'tampered'].contains(checkpoint),
        );
        expect(
          await (await files.bookFile('other-book', 'source')).readAsBytes(),
          [1, 2, 3],
        );
        expect(source.original, [1, 2, 3, 4]);
      },
    );
  }
  test('only one operation runs and cancellation during copy never exposes a draft', () async {
    final dir = await Directory.systemTemp.createTemp('epub-cancel-copy-');
    addTearDown(() => dir.delete(recursive: true));
    final files = await BookFileStore.open(dir);
    final source = ImportSource(files)..pauseCopy = Completer<void>();
    final importer = BookImporter(
      source: source,
      books: books,
      files: files,
      normalizeKey: (s) async => s,
    );
    final pending = importer.importBook('op', 'book', 1);
    await source.copyEntered.future;
    await expectLater(
      importer.importBook('other-op', 'other-book', 1),
      throwsA(
        isA<BookFailure>().having(
          (e) => e.code,
          'code',
          BookError.operationInProgress,
        ),
      ),
    );
    expect(await importer.cancel(), true);
    expect((await pending).cancelled, true);
    expect(await books.readyPage(), isEmpty);
    expect(await (await files.stagingFile('op', 'source')).exists(), false);
  });
  test(
    'concurrent source reservations have one winner and one recoverable loser',
    () async {
      await books.begin('one-op', 'one', 1);
      await books.begin('two-op', 'two', 1);
      final outcomes = await Future.wait([
        for (final id in ['one', 'two'])
          books
              .reserve('$id-op', id, 'c' * 64, 1)
              .then(
                (_) => 'reserved',
                onError: (Object e) => e is BookFailure ? 'conflict' : throw e,
              ),
      ]);
      expect(outcomes.where((s) => s == 'reserved').length, 1);
      expect(outcomes.where((s) => s == 'conflict').length, 1);
      final rows = await db
          .customSelect(
            'SELECT book_id FROM books WHERE source_sha256 IS NOT NULL',
          )
          .get();
      expect(rows.length, 1);
    },
  );
  test('retry after a failed final validation automatically releases the old reservation', () async {
    final dir = await Directory.systemTemp.createTemp('epub-retry-');
    addTearDown(() => dir.delete(recursive: true));
    final files = await BookFileStore.open(dir);
    final first = BookImporter(
      source: ImportSource(files),
      books: FaultBooks(db, 'before-validated', files),
      files: files,
      normalizeKey: (s) async => s,
    );
    await expectLater(
      first.importBook('op', 'book', 1),
      throwsA(isA<BookFailure>()),
    );
    final retry = BookImporter(
      source: ImportSource(files),
      books: books,
      files: files,
      normalizeKey: (s) async => s,
    );
    final result = await retry.importBook('retry-op', 'retry-book', 1);
    expect(result.book!.key.id, 'retry-book');
    expect((await books.readyPage()).length, 1);
    expect(await (await files.stagingFile('op', 'source')).exists(), false);
  });
  test('shutdown waits for an active import to finish cleanup before database disposal', () async {
    final dir = await Directory.systemTemp.createTemp('epub-shutdown-');
    addTearDown(() => dir.delete(recursive: true));
    final files = await BookFileStore.open(dir);
    final source = ImportSource(files)..pauseCopy = Completer<void>();
    final importer = BookImporter(
      source: source,
      books: books,
      files: files,
      normalizeKey: (s) async => s,
    );
    final pending = importer.importBook('op', 'book', 1);
    await source.copyEntered.future;
    await importer.shutdown();
    expect((await pending).cancelled, true);
    expect(await books.readyPage(), isEmpty);
    await expectLater(
      importer.importBook('later', 'later-book', 1),
      throwsA(isA<BookFailure>()),
    );
  });
}

class ImportSource implements EpubImportSource {
  ImportSource(this.files);
  final BookFileStore files;
  final original = [1, 2, 3];
  Object? copyFailure;
  Completer<void>? pauseCopy;
  final copyEntered = Completer<void>();
  bool wasCancelled = false;
  String op = '';
  bool selectCancelled = false, badUnused = false, verified = false;
  @override
  String? get displayName => 'Source.epub';
  @override
  Future<String?> choose(String operationId, int generation) async {
    op = operationId;
    wasCancelled = false;
    return selectCancelled ? null : 'h';
  }

  @override
  Future<({String sha256, int bytes})> copyAndHash(
    String handle, {
    void Function(int)? progress,
  }) async {
    if (!copyEntered.isCompleted) copyEntered.complete();
    await pauseCopy?.future;
    if (wasCancelled) throw const BookFailure(BookError.cancelled);
    if (copyFailure != null) throw copyFailure!;
    await files.writeStaged(
      op,
      'source',
      Stream.value(original),
      maxBytes: original.length,
    );
    progress?.call(original.length);
    return (
      sha256: sha256.convert(original).toString(),
      bytes: original.length,
    );
  }

  @override
  Future<VerifiedEpubArchive> openArchive() async => ImportArchive(this);
  @override
  Future<void> cancel(String operation, int generation) async {
    wasCancelled = true;
    if (pauseCopy?.isCompleted == false) pauseCopy!.complete();
  }

  @override
  Future<void> close(String handle) async {}
  @override
  Future<BookSourceChunk> read(String handle, {int maxBytes = 65536}) async =>
      throw UnimplementedError();
}

class ImportArchive implements VerifiedEpubArchive {
  ImportArchive(this.source);
  final ImportSource source;
  final data = fixture();
  @override
  List<String> get names => data.keys.toList();
  @override
  Future<Uint8List> read(String name, {required int maxBytes}) async {
    final bytes = utf8.encode(data[name]!);
    if (bytes.length > maxBytes) {
      throw const BookFailure(BookError.limitExceeded);
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> close() async {}
  @override
  Future<void> verifyRemaining() async {
    if (source.badUnused) throw const BookFailure(BookError.invalidArchive);
    source.verified = true;
  }
}

class FaultBooks extends BookRepository {
  FaultBooks(super.db, this.checkpoint, this.files);
  final String checkpoint;
  final BookFileStore files;
  @override
  Future<void> validated(
    String op,
    String book,
    String manifest,
    String proof,
  ) async {
    if (checkpoint == 'before-validated') {
      throw StateError('simulated interruption');
    }
    await super.validated(op, book, manifest, proof);
    if (checkpoint == 'tampered') {
      await (await files.stagingFile(op, 'source')).writeAsBytes([9]);
      throw StateError('simulated interruption');
    }
    if (checkpoint == 'validated') throw StateError('simulated interruption');
  }

  @override
  Future<void> commitReady(String op, String book, String manifest) async {
    if (checkpoint == 'renamed') throw StateError('simulated interruption');
    await super.commitReady(op, book, manifest);
    if (checkpoint == 'committed') throw StateError('simulated interruption');
  }
}
