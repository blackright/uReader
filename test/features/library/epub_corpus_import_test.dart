import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/library/book_importer.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';
import 'package:prototype/infrastructure/database/book_content_repository.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';
import 'package:prototype/infrastructure/epub/epub_import_source.dart';
import 'package:prototype/infrastructure/epub/epub_package_parser.dart';

// Injected authorized fixtures: this does NOT exercise Android SAF or native CRC.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/epub_packages.json').readAsStringSync(),
  ) as Map;
  for (final raw in fixture['books'] as List) {
    final entry = raw as Map;
    final id = entry['id'] as String;
    test('isolated corpus import and windowed opening: $id', () async {
      final dir = await Directory.systemTemp.createTemp('epub-corpus-');
      addTearDown(() => dir.delete(recursive: true));
      final db = PrototypeDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final books = BookRepository(db);
      final files = await BookFileStore.open(dir);
      final source = FixtureSource(files, entry);
      final importer = BookImporter(
        source: source,
        books: books,
        files: files,
        normalizeKey: (s) async => s.toLowerCase(),
      );
      final result = await importer.importBook('op', id, 1);
      expect(result.book, isNotNull);
      expect(source.verified, true);
      final content = BookContentRepository(db, files);
      final chapters = await content.chapters(result.book!.key);
      expect(chapters.length, (entry['reference']['chapters'] as List).length);
      BookCursor? after;
      final texts = <String>[];
      final actual = <String, String>{};
      do {
        final window = await content.window(result.book!.key, 1, after: after);
        expect(window.blocks.length, lessThanOrEqualTo(64));
        expect(
          window.blocks.fold<int>(0, (n, b) => n + b.text.length),
          lessThanOrEqualTo(65536),
        );
        texts.addAll(window.blocks.map((b) => b.text));
        actual.addAll({for (final b in window.blocks) b.id: b.text});
        after = window.next;
      } while (after != null);
      expect(texts.join(), isNotEmpty);
      for (final chapter in entry['reference']['chapters'] as List) {
        for (final block in chapter['initialCanonicalBlocks'] as List) {
          expect(
            actual[block['id']],
            block['text'],
            reason: '$id ${block['id']}',
          );
        }
      }
      if (int.parse(id.split('-').last) <= 5) {
        source.renamedName = 'renamed-$id.epub';
      }
      final repeat = await importer.importBook('op2', 'renamed-$id', 1);
      expect(repeat.existing, true);
      expect(repeat.book!.key.id, id);
      expect(repeat.book!.title, result.book!.title);
      expect((await books.readyPage()).length, 1);
    });
  }
}

class FixtureSource implements EpubImportSource {
  FixtureSource(this.files, this.fixture);
  final BookFileStore files;
  final Map fixture;
  String? renamedName;
  String op = '';
  bool verified = false;
  @override
  String? get displayName => renamedName ?? '${fixture['id']}.epub';
  @override
  Future<String?> choose(String operation, int generation) async {
    op = operation;
    return 'h';
  }

  @override
  Future<({String sha256, int bytes})> copyAndHash(
    String h, {
    void Function(int)? progress,
  }) async {
    final bytes = base64Decode(fixture['source'] as String);
    await files.writeStaged(
      op,
      'source',
      Stream.value(bytes),
      maxBytes: bytes.length,
    );
    progress?.call(bytes.length);
    return (sha256: sha256.convert(bytes).toString(), bytes: bytes.length);
  }

  @override
  Future<VerifiedEpubArchive> openArchive() async => FixtureArchive(this);
  @override
  Future<void> close(String h) async {}
  @override
  Future<void> cancel(String op, int generation) async {}
  @override
  Future<BookSourceChunk> read(String h, {int maxBytes = 65536}) async =>
      throw UnimplementedError();
}

class FixtureArchive implements VerifiedEpubArchive {
  FixtureArchive(this.source);
  final FixtureSource source;
  Map get data => source.fixture['entries'] as Map;
  @override
  List<String> get names => data.keys.cast<String>().toList();
  @override
  Future<Uint8List> read(String name, {required int maxBytes}) async {
    final value = data[name];
    if (value is! String) throw const BookFailure(BookError.invalidArchive);
    final bytes = base64Decode(value);
    if (bytes.length > maxBytes) {
      throw const BookFailure(BookError.limitExceeded);
    }
    return bytes;
  }

  @override
  Future<void> close() async {}
  @override
  Future<void> verifyRemaining() async {
    source.verified = true;
  }
}
