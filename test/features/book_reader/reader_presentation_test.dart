import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/features/book_reader/book_reader_controller.dart';
import 'package:prototype/features/book_reader/book_reader_screen.dart';
import 'package:prototype/infrastructure/database/book_position_repository.dart';
import 'package:prototype/infrastructure/database/book_preferences_repository.dart';

import 'reader_fixture.dart';

Future<void> ready(WidgetTester tester, BookReaderController reader) async {
  for (var i = 0; i < 300 && (reader.window == null || reader.loading); i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  expect(reader.error, isNull);
  expect(reader.window, isNotNull);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'theme, font and recreation preserve the durable UTF16 locator at large system scale',
    (tester) async {
      final f = ReaderFixture();
      await tester.runAsync(f.open);
      addTearDown(f.close);
      final key = (await tester.runAsync(
        () => f.book('book', text: 'Un passage long. ' * 50),
      ))!;
      final positions = BookPositionRepository(f.db, f.content),
          prefs = BookPreferencesRepository(f.db);
      final where = BookLocator(
        key: key,
        chapterId: 'c0',
        blockId: 'b3',
        offsetUtf16: 10,
      );
      await positions.save(where, ReadingMode.visual, expectedRevision: 0);
      final book = Book(
        key: key,
        title: 'Mon livre',
        authors: [],
        languages: ['fr'],
      );
      BookReaderController controller() => BookReaderController(
        book: book,
        content: f.content,
        positions: positions,
        preferenceStore: prefs,
      );
      Widget app(BookReaderController c) => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(3.2)),
          child: child!,
        ),
        home: BookReaderScreen(book: book, content: f.content, controller: c),
      );
      final reader = controller();
      await tester.pumpWidget(app(reader));
      await ready(tester, reader);
      expect(reader.focusLocator!.offsetUtf16, 10);
      await tester.tap(find.byTooltip('Réglages de lecture'));
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(1.5);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Sombre'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Sombre'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sombre'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Appliquer'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 100 && reader.preferences.theme != ReaderTheme.dark;
        i++
      ) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      await ready(tester, reader);
      await reader.flush();
      final after = await positions.read(key, ReadingMode.visual);
      expect(after!.locator.blockId, 'b3');
      expect(after.locator.offsetUtf16, 10);
      expect(after.revision, 1);
      expect(reader.preferences.fontScale, 1.5);
      expect(reader.preferences.theme, ReaderTheme.dark);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await reader.close();
      final reopened = controller();
      await tester.pumpWidget(app(reopened));
      await ready(tester, reopened);
      expect(reopened.focusLocator!.blockId, 'b3');
      expect(reopened.focusLocator!.offsetUtf16, 10);
      expect(reopened.preferences.fontScale, 1.5);
      await tester.pumpWidget(const SizedBox());
      await reopened.close();
    },
  );
  test('incompatible stored offset proposes a fallback without pretending exact restore', () async {
    final f = ReaderFixture();
    await f.open();
    addTearDown(f.close);
    final key = await f.book('book');
    await f.db.customStatement(
      "INSERT INTO book_positions VALUES (?,'visual',1,'c0','b0',7,1,1)",
      ['book'],
    );
    final reader = BookReaderController(
      book: Book(key: key, title: 'Livre', authors: [], languages: ['fr']),
      content: f.content,
      positions: BookPositionRepository(f.db, f.content),
    );
    await reader.initialize();
    expect(reader.window, isNull);
    expect(reader.fallbackChapter, 'c0');
    expect(reader.warning, contains('incompatible'));
    await reader.fallback();
    await reader.flush();
    expect(reader.window!.blocks.first.id, 'b0');
    expect(reader.durable!.offsetUtf16, 0);
    await reader.close();
  });
  test('a stored projection version cannot be silently interpreted as current content', () async {
    final f = ReaderFixture();
    await f.open();
    addTearDown(f.close);
    final key = await f.book('versioned');
    await f.db.customStatement(
      "INSERT INTO book_positions VALUES (?,'visual',1,'c0','b0',0,1,1)",
      ['versioned'],
    );
    final reader = BookReaderController(
      book: Book(key: key, title: 'Livre', authors: [], languages: ['fr']),
      content: f.content,
      positions: StaleVersionPositions(f),
    );
    await reader.initialize();
    expect(reader.window, isNull);
    expect(reader.warning, contains('incompatible'));
    await reader.fallback();
    await reader.flush();
    expect(reader.durable!.key.version, 1);
    await reader.close();
  });
}

class StaleVersionPositions extends BookPositionRepository {
  StaleVersionPositions(ReaderFixture f) : super(f.db, f.content);
  @override
  Future<BookPosition?> read(ContentKey key, ReadingMode mode) async {
    final value = await super.read(key, mode);
    if (value == null) return null;
    return BookPosition(
      BookLocator(
        key: ContentKey(ContentKind.book, key.id, 2),
        chapterId: value.locator.chapterId,
        blockId: value.locator.blockId,
        offsetUtf16: value.locator.offsetUtf16,
      ),
      mode,
      value.revision,
    );
  }
}
