import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/features/library/library_controller.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';

import '../book_reader/reader_fixture.dart';

void main() {
  test(
    'query normalization stays delegated to the existing ICU port',
    () async {
      final f = ReaderFixture();
      await f.open();
      addTearDown(f.close);
      await f.book('accented', blocks: 1, chapters: 1);
      await f.db.customStatement(
        "UPDATE books SET title='Été',title_key='ete',author_key='strasse' WHERE book_id='accented'",
      );
      final calls = <String>[];
      final controller = LibraryController(
        BookRepository(f.db),
        normalizeKey: (input) async {
          calls.add(input);
          return switch (input) {
            'ÉTÉ' => 'ete',
            'Straße' => 'strasse',
            _ => input,
          };
        },
      );
      addTearDown(controller.dispose);
      await controller.refresh(search: 'ÉTÉ');
      expect(controller.books.single.title, 'Été');
      await controller.refresh(search: 'Straße');
      expect(controller.books.single.key.id, 'accented');
      expect(calls, ['ÉTÉ', 'Straße']);
    },
  );
  test(
    'a late normalization cannot poison the next page of the newest query',
    () async {
      final f = ReaderFixture();
      await f.open();
      addTearDown(f.close);
      for (var i = 0; i < 53; i++) {
        await f.book(
          'new-${i.toString().padLeft(3, '0')}',
          blocks: 1,
          chapters: 1,
        );
      }
      await f.book('old-only', blocks: 1, chapters: 1);
      final pending = <String, Completer<String>>{};
      final library = LibraryController(
        BookRepository(f.db),
        normalizeKey: (input) => (pending[input] = Completer<String>()).future,
      );
      addTearDown(library.dispose);
      final old = library.refresh(search: 'old');
      final latest = library.refresh(search: 'new');
      pending['new']!.complete('new');
      await latest;
      expect(library.books, hasLength(50));
      pending['old']!.complete('old');
      await old;
      await library.nextPage();
      expect(library.books, hasLength(53));
      expect(library.books.every((b) => b.key.id.startsWith('new-')), true);
    },
  );
  test('literal searches and stable title/author/recent pagination do not mutate books', () async {
    final f = ReaderFixture();
    await f.open();
    addTearDown(f.close);
    for (var i = 0; i < 53; i++) {
      final id = 'search-${i.toString().padLeft(3, '0')}';
      await f.book(id, blocks: 1, chapters: 1);
      await f.db.customStatement(
        "UPDATE books SET title_key='ete %_',author_key='lea',created_at=? WHERE book_id=?",
        [i, id],
      );
    }
    final repo = BookRepository(f.db);
    for (final sort in BookSort.values) {
      final first = await repo.page(search: '%_', sort: sort);
      expect(first.books.length, 50);
      final rest = await repo.page(
        search: '%_',
        sort: sort,
        afterKey: first.nextKey,
        afterId: first.nextId,
      );
      expect(
        {
          ...first.books.map((b) => b.key.id),
          ...rest.books.map((b) => b.key.id),
        }.length,
        53,
      );
    }
    expect(
      (await repo.readyPage(sort: BookSort.recent)).first.key.id,
      'search-052',
    );
    expect((await repo.readyPage(search: 'lea')).length, 50);
    expect(await repo.readyPage(search: "' OR 1=1 --"), isEmpty);
    expect(
      (await f.db.customSelect('SELECT count(*) n FROM books').getSingle())
          .read<int>('n'),
      53,
    );
  });
}
