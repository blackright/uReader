import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/pagination.dart';
import 'package:prototype/features/book_reader/book_pagination_controller.dart';
import 'package:prototype/features/book_reader/book_paginator.dart';
import 'package:prototype/features/book_reader/book_reader_controller.dart';
import 'package:prototype/domain/reader_experience.dart';
import 'package:prototype/infrastructure/database/experience_preferences_repository.dart';
import 'package:prototype/features/book_reader/reader_layout.dart';
import 'package:prototype/infrastructure/database/page_index_repository.dart';

import 'reader_fixture.dart';

Future<void> settled(BookPaginationController controller) async {
  final watch = Stopwatch()..start();
  while (controller.calculating) {
    if (watch.elapsed > const Duration(seconds: 30)) {
      fail('Pagination did not finish');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ReaderFixture fixture;
  setUp(() async {
    fixture = ReaderFixture();
    await fixture.open();
  });
  tearDown(() => fixture.close());
  test(
    'scroll window does not end a logical paragraph at a projection slice',
    () async {
      final key = await fixture.book(
        'sliced',
        blocks: 9,
        chapters: 1,
        text: 'mot ' * 2048,
      );
      for (var n = 0; n < 9; n++) {
        await fixture.db.customStatement(
          'UPDATE book_blocks SET block_id=? WHERE book_id=? AND ordinal=?',
          ['c0-b0-s$n', key.id, n],
        );
      }
      final prefs = ExperiencePreferencesRepository(fixture.db);
      await prefs.save(ExperiencePreferences(mode: ReaderMode.scroll));
      final reader = BookReaderController(
        book: Book(key: key, title: 'Tranches', authors: [], languages: ['fr']),
        content: fixture.content,
        experienceStore: prefs,
        pageIndexStore: PageIndexRepository(fixture.db),
      );
      await reader.initialize();
      expect(reader.error, isNull);
      expect(reader.window!.blocks.length, 8);
      expect(reader.paragraphEnds(reader.window!.blocks.last), isFalse);
      await reader.next();
      expect(reader.window!.blocks.single.id, 'c0-b0-s8');
      expect(reader.paragraphEnds(reader.window!.blocks.single), isTrue);
      await reader.close();
    },
  );
  test('preview has no invented number, index completes and twenty turns stay bounded', () async {
    final key = await fixture.book(
      'pager',
      blocks: 12,
      text: 'Un passage à lire. ' * 45,
    );
    final seen = <BookLocator>[];
    final controller = BookPaginationController(
      key: key,
      source: fixture.content,
      index: PageIndexRepository(fixture.db),
      onVisible: (locator, _) => seen.add(locator),
    );
    var previewObserved = false;
    controller.addListener(() {
      expect(controller.retainedPages, lessThanOrEqualTo(3));
      if (controller.calculating) expect(controller.total, isNull);
      if (controller.current != null && controller.pageNumber == null) {
        previewObserved = true;
      }
    });
    await controller.configure(
      ReaderLayout(width: 250, height: 240),
      BookLocator(key: key, chapterId: 'c1', blockId: 'b7', offsetUtf16: 15),
    );
    await settled(controller);
    expect(controller.error, isNull);
    expect(previewObserved, isTrue);
    expect(controller.total, greaterThan(20));
    expect(controller.pageNumber, greaterThan(1));
    expect(seen, isEmpty); // Restoring a preview never writes a new position.
    final firstNumber = controller.pageNumber!;
    for (var n = 0; n < 20; n++) {
      await controller.turn(n.isEven);
      expect(controller.error, isNull);
      expect(controller.retainedPages, lessThanOrEqualTo(3));
    }
    expect(controller.pageNumber, firstNumber);
    expect(seen.length, 20);
    await controller.close();
    expect(
      (await fixture.db
              .customSelect('SELECT COUNT(*) AS n FROM book_page_runs')
              .getSingle())
          .read<int>('n'),
      0,
    );
  });
  test(
    'late empty lookup cannot erase neighbor supplied by ongoing scan',
    () async {
      final key = await fixture.book(
        'race',
        blocks: 4,
        text: 'Paragraphe long. ' * 60,
      );
      final store = GatedPageIndex(fixture.db);
      final controller = BookPaginationController(
        key: key,
        source: fixture.content,
        index: store,
        onVisible: (_, _) {},
      );
      try {
        await controller.configure(
          ReaderLayout(width: 220, height: 180),
          BookLocator(key: key, chapterId: 'c0', blockId: 'b0', offsetUtf16: 0),
        );
        await store.prefixReady.future;
        final turn = controller.turn(true);
        await store.lookupReady.future;
        store.continueScan.complete();
        for (var i = 0; i < 1000 && controller.next?.ordinal != 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        expect(controller.next?.ordinal, 2);
        store.continueLookup.complete();
        await turn;
        expect(controller.next?.ordinal, 2);
        await settled(controller);
        expect(controller.error, isNull);
      } finally {
        if (!store.continueScan.isCompleted) store.continueScan.complete();
        if (!store.continueLookup.isCompleted) store.continueLookup.complete();
        await controller.close();
      }
    },
  );
  test(
    'replaced layout retains target and old generation cannot publish',
    () async {
      final key = await fixture.book(
        'replace',
        blocks: 8,
        text: 'Paragraphe. ' * 30,
      );
      final controller = BookPaginationController(
        key: key,
        source: fixture.content,
        index: PageIndexRepository(fixture.db),
        onVisible: (_, _) {},
      );
      final old = controller.configure(
        ReaderLayout(width: 200, height: 240),
        BookLocator(key: key, chapterId: 'c0', blockId: 'b0', offsetUtf16: 0),
      );
      final target = BookLocator(
        key: key,
        chapterId: 'c1',
        blockId: 'b6',
        offsetUtf16: 19,
      );
      final latest = controller.configure(
        ReaderLayout(width: 280, height: 300),
        target,
      );
      await Future.wait([old, latest]);
      await settled(controller);
      expect(controller.generation, 2);
      expect(controller.error, isNull);
      final point = PagePoint(6, 19);
      expect(controller.current!.start.compareTo(point), lessThanOrEqualTo(0));
      expect(controller.current!.end.compareTo(point), greaterThan(0));
      await controller.close();
    },
  );
  test('Unicode context survives disk boundary reconstruction on both sides of seam', () async {
    final key = await fixture.book('context-cache', blocks: 2, chapters: 1);
    final texts = ['mot ' * 1000 + 'e', '\u0301 suite' * 500];
    for (var n = 0; n < 2; n++) {
      await fixture.db.customStatement(
        'UPDATE book_blocks SET block_id=?,source_text=?,text_units=? WHERE book_id=? AND ordinal=?',
        ['c0-b0-s$n', texts[n], texts[n].length, key.id, n],
      );
    }
    final controller = BookPaginationController(
      key: key,
      source: fixture.content,
      index: PageIndexRepository(fixture.db),
      onVisible: (_, _) {},
    );
    await controller.configure(
      ReaderLayout(width: 250, height: 260),
      BookLocator(
        key: key,
        chapterId: 'c0',
        blockId: 'c0-b0-s1',
        offsetUtf16: 100,
      ),
    );
    await settled(controller);
    expect(controller.error, isNull);
    final initial = controller.current!.start;
    for (var n = 0; n < 12; n++) {
      await controller.turn(n.isEven);
      expect(controller.error, isNull);
      expect(controller.retainedPages, lessThanOrEqualTo(3));
    }
    expect(controller.current!.start, initial);
    await controller.close();
  });
  test(
    'split combining cluster is shaped together without changing source',
    () async {
      final key = await fixture.book('unicode', blocks: 2, chapters: 1);
      await fixture.db.customStatement(
        "UPDATE book_blocks SET block_id='c0-b0-s0',source_text='e' WHERE book_id='unicode' AND ordinal=0",
      );
      await fixture.db.customStatement(
        "UPDATE book_blocks SET block_id='c0-b0-s1',source_text=? WHERE book_id='unicode' AND ordinal=1",
        ['\u0301 suite'],
      );
      final blocks = await fixture.content.window(key, 1);
      final pages = await BookPaginator(ReaderLayout(width: 250, height: 300))
          .paginate(Stream.fromIterable(blocks.blocks))
          .toList();
      expect(
        pages
            .expand((p) => p.fragments)
            .map((f) => f.block.text.substring(f.startUtf16, f.endUtf16))
            .join(),
        'e\u0301 suite',
      );
      expect(pages.first.fragments.first.context!.text, 'e\u0301 suite');
      expect((await fixture.content.block(key, 'c0-b0-s0')).text, 'e');
      expect(
        (await fixture.content.block(key, 'c0-b0-s1')).text,
        '\u0301 suite',
      );
    },
  );
}

class GatedPageIndex extends PageIndexRepository {
  GatedPageIndex(super.db);
  final prefixReady = Completer<void>(), lookupReady = Completer<void>();
  final continueScan = Completer<void>(), continueLookup = Completer<void>();
  @override
  Future<void> append(
    String handle,
    List<PageBoundary> pages, {
    required int generation,
    required bool complete,
  }) async {
    await super.append(
      handle,
      pages,
      generation: generation,
      complete: complete,
    );
    if (pages.any((page) => page.ordinal == 1) && !prefixReady.isCompleted) {
      prefixReady.complete();
      await continueScan.future;
    }
  }

  @override
  Future<List<PageBoundary>> boundaries(
    String handle,
    int first, {
    int limit = 128,
  }) async {
    final result = await super.boundaries(handle, first, limit: limit);
    if (first == 2 && result.isEmpty && !lookupReady.isCompleted) {
      lookupReady.complete();
      await continueLookup.future;
    }
    return result;
  }
}
