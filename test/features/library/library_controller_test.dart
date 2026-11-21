import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/library/library_controller.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';

void main() {
  test('53 equal search keys paginate by identity without losing or repeating a book', () async {
    final db = PrototypeDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = BookRepository(db);
    for (var i = 0; i < 53; i++) {
      final id = 'book-${i.toString().padLeft(2, '0')}';
      await db.customStatement(
        "INSERT INTO books(book_id,source_sha256,source_bytes,title,authors_json,languages_json,title_key,author_key,search_key_version,created_at,updated_at,state,projection_version,manifest_sha256,last_mode) VALUES (?,?,1,'Même titre','[]','[]','identique','',1,0,0,'ready',1,?,'visual')",
        [id, (i + 1).toRadixString(16).padLeft(64, '0'), 'f' * 64],
      );
    }
    final controller = LibraryController(
      repository,
      normalizeKey: (s) async => s,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.books.length, 50);
    expect(controller.hasMore, true);
    await controller.nextPage();
    expect(controller.books.length, 53);
    expect(controller.books.map((b) => b.key.id).toSet().length, 53);
    expect(controller.hasMore, false);
    await controller.refresh(search: '%');
    expect(controller.books, isEmpty);
  });
  test('a late result cannot replace a newer search', () async {
    final db = PrototypeDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = DelayedRepository(db);
    final controller = LibraryController(
      repository,
      normalizeKey: (s) async => s,
    );
    addTearDown(controller.dispose);
    final old = controller.refresh(search: 'old');
    await Future<void>.delayed(Duration.zero);
    final latest = controller.refresh(search: 'new');
    await Future<void>.delayed(Duration.zero);
    Book book(String id) => Book(
      key: ContentKey(ContentKind.book, id, 1),
      title: id,
      authors: [],
      languages: [],
    );
    repository.requests['new']!.complete((
      books: [book('new')],
      nextKey: null,
      nextId: null,
    ));
    await latest;
    repository.requests['old']!.complete((
      books: [book('old')],
      nextKey: null,
      nextId: null,
    ));
    await old;
    expect(controller.books.single.key.id, 'new');
  });
}

typedef Page = ({List<Book> books, String? nextKey, String? nextId});

class DelayedRepository extends BookRepository {
  DelayedRepository(super.db);
  final requests = <String, Completer<Page>>{};
  @override
  Future<Page> page({
    String? afterKey,
    String? afterId,
    String search = '',
    BookSort sort = BookSort.title,
  }) => (requests[search] = Completer<Page>()).future;
}
