import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/domain/reader_experience.dart';
import 'package:prototype/features/book_reader/book_reader_controller.dart';

void main() {
  test('experience loads and saves atomically with typography; failures preserve passage', () async {
    final source = ControlledSource();
    final store = TestExperienceStore();
    final reader = BookReaderController(
      book: Book(
        key: ControlledSource.key,
        title: 'Livre',
        authors: [],
        languages: ['fr'],
      ),
      content: source,
      experienceStore: store,
    );
    await reader.initialize();
    expect(reader.experience.mode, ReaderMode.scroll);
    final passage = reader.visible;
    await reader.changeExperience(
      ExperiencePreferences(
        mode: ReaderMode.paged,
        lineHeight: 1.8,
        margins: 28,
      ),
      readerValue: ReaderPreferences(fontScale: 1.5, theme: ReaderTheme.dark),
    );
    expect(store.writes, 1);
    expect(store.typography!.fontScale, 1.5);
    expect(reader.preferences.theme, ReaderTheme.dark);
    expect(reader.experience.margins, 28);
    expect(reader.visible, passage);
    final accepted = reader.experience;
    store.fail = true;
    await reader.changeExperience(
      ExperiencePreferences(mode: ReaderMode.scroll),
    );
    expect(reader.experience, same(accepted));
    expect(reader.visible, passage);
    expect(reader.warning, contains('ne sont pas enregistrés'));
    await reader.close();
  });
  test('late page cannot replace new consultation; windows and leases remain bounded', () async {
    final source = ControlledSource(),
        book = Book(
          key: ControlledSource.key,
          title: 'Livre',
          authors: [],
          languages: ['fr'],
        );
    final reader = BookReaderController(book: book, content: source);
    await reader.initialize();
    source.delay = Completer<BookWindow>();
    final old = reader.next();
    await Future<void>.delayed(Duration.zero);
    final staleGeneration = source.lastGeneration;
    await reader.go(
      BookLocator(
        key: book.key,
        chapterId: 'c0',
        blockId: 'b0',
        offsetUtf16: 0,
      ),
    );
    source.delay!.complete(source.page(1, staleGeneration));
    await old;
    expect(reader.window!.blocks.first.id, 'b0');
    source.delay = null;
    for (var i = 0; i < 20; i++) {
      await reader.next();
      expect(reader.retainedWindows, lessThanOrEqualTo(2));
    }
    await reader.close();
    expect(source.lease.released, true);
  });
}

class TestLease implements ContentLease {
  bool released = false;
  @override
  Future<void> release() async {
    released = true;
  }
}

class ControlledSource implements BookContentSource {
  static final key = ContentKey(ContentKind.book, 'book', 1);
  final lease = TestLease();
  Completer<BookWindow>? delay;
  int lastGeneration = 0;
  BookWindow page(int ordinal, int g) => BookWindow(
    key: key,
    generation: g,
    blocks: [
      BookBlock(
        key: key,
        chapterId: 'c0',
        id: 'b$ordinal',
        ordinal: ordinal,
        kind: BookBlockKind.paragraph,
        text: 'Passage $ordinal',
      ),
    ],
    next: BookCursor(key: key, generation: g, nextOrdinal: ordinal + 1),
  );
  @override
  Future<BookWindow> window(
    ContentKey key,
    int generation, {
    BookCursor? after,
    int maxBlocks = 64,
    int maxUnits = 65536,
  }) async {
    lastGeneration = generation;
    if (after != null && delay != null) return delay!.future;
    return page(after?.nextOrdinal ?? 0, generation);
  }

  @override
  Future<List<BookChapter>> chapters(ContentKey key) async => [];
  @override
  Future<ContentLease> acquire(ContentKey key) async => lease;
  @override
  Future<void> validateLocator(BookLocator locator) async {}
  @override
  Future<BookLocator> resolveAnchor(
    ContentKey key,
    String resource,
    String fragment,
  ) async => throw const BookFailure(BookError.invalidLocator);
}

class TestExperienceStore implements ExperiencePreferenceStore {
  ExperiencePreferences value = ExperiencePreferences(mode: ReaderMode.scroll);
  ReaderPreferences? typography;
  int writes = 0;
  bool fail = false;
  @override
  Future<ExperiencePreferences> read() async => value;
  @override
  Future<void> save(
    ExperiencePreferences next, {
    ReaderPreferences? reader,
  }) async {
    if (fail) throw const BookFailure(BookError.storageUnavailable);
    writes++;
    value = next;
    typography = reader;
  }

  @override
  Future<void> flush() async {}
}
