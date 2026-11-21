import 'dart:io';

import 'package:crypto/crypto.dart';

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/database/book_content_repository.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';

class ReaderFixture {
  late Directory dir;
  late PrototypeDatabase db;
  late BookContentRepository content;
  Future<void> open() async {
    dir = await Directory.systemTemp.createTemp('ureader-reader4-');
    dir = Directory(await dir.resolveSymbolicLinks());
    db = PrototypeDatabase(NativeDatabase.memory());
    await db.initialize();
    content = BookContentRepository(db, await BookFileStore.open(dir));
  }

  Future<ContentKey> book(
    String id, {
    int blocks = 8,
    String text = 'Texte 😀 du passage',
    int chapters = 2,
  }) async {
    final sha = sha256.convert(utf8.encode(id)).toString();
    await db.customStatement(
      "INSERT INTO books(book_id,source_sha256,source_bytes,title,authors_json,languages_json,title_key,author_key,search_key_version,created_at,updated_at,state,projection_version,manifest_sha256,last_mode) VALUES (?,?,1,?,'[]','[\"fr\"]',?,'',1,1,1,'ready',1,?,'visual')",
      [id, sha, id, id, sha],
    );
    await Directory('${dir.path}/books/$id').create(recursive: true);
    await db.transaction(() async {
      var units = 0;
      for (var chapter = 0; chapter < chapters; chapter++) {
        final start = chapter * blocks ~/ chapters,
            end = (chapter + 1) * blocks ~/ chapters;
        await db.customStatement(
          'INSERT INTO book_chapters VALUES (?,?,?,?,?,?,?,?)',
          [
            id,
            'c$chapter',
            chapter,
            'OPS/c$chapter.xhtml',
            'Chapitre ${chapter + 1}',
            start,
            end - start,
            (end - start) * text.length,
          ],
        );
        for (var i = start; i < end; i++) {
          await db.customStatement(
            'INSERT INTO book_blocks VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
            [
              id,
              'b$i',
              'c$chapter',
              i,
              'paragraph',
              text,
              text.length,
              '[]',
              1,
              null,
              null,
              null,
              units,
            ],
          );
          units += text.length;
        }
      }
    });
    return ContentKey(ContentKind.book, id, 1);
  }

  Future<void> close() async {
    await db.close();
    await dir.delete(recursive: true);
  }
}
