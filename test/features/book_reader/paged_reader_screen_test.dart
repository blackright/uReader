import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/domain/reader_experience.dart';
import 'package:prototype/features/book_reader/book_reader_controller.dart';
import 'package:prototype/features/book_reader/book_reader_screen.dart';
import 'package:prototype/features/book_reader/paged_book_view.dart';
import 'package:prototype/infrastructure/database/book_position_repository.dart';
import 'package:prototype/infrastructure/database/book_preferences_repository.dart';
import 'package:prototype/infrastructure/database/experience_preferences_repository.dart';
import 'package:prototype/infrastructure/database/page_index_repository.dart';

import 'reader_fixture.dart';

Future<void> settleReader(
  WidgetTester tester,
  BookReaderController reader, {
  bool saved = false,
}) async {
  for (var i = 0; i < 800; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (!reader.loading &&
        reader.pagination?.calculating != true &&
        reader.pagination?.navigating != true &&
        (!saved ||
            (reader.durable?.blockId == reader.visible?.blockId &&
                reader.durable?.offsetUtf16 == reader.visible?.offsetUtf16))) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(reader.pagination?.error, isNull);
      expect(tester.takeException(), isNull);
      return;
    }
  }
  fail(
    'Reader did not settle: loading=${reader.loading}, calculating=${reader.pagination?.calculating}, generation=${reader.pagination?.generation}, prefix=${reader.pagination?.prefixPages}, error=${reader.pagination?.error}',
  );
}

Future<void> runReaderOperation(
  WidgetTester tester,
  Future<void> Function() operation,
) async {
  var done = false;
  Object? failure;
  operation().then(
    (_) => done = true,
    onError: (Object e) {
      failure = e;
      done = true;
    },
  );
  for (var i = 0; i < 1200 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(done, isTrue, reason: 'Reader operation did not finish');
  if (failure != null) throw failure!;
}

Future<void> waitForReaderControl(WidgetTester tester, Finder control) async {
  for (var i = 0; i < 200 && control.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  await tester.pumpAndSettle();
  expect(control, findsWidgets);
}

void main() {
  testWidgets(
    'product pages persist passage across typography, mode and reopen',
    (tester) async {
      final f = ReaderFixture();
      await tester.runAsync(f.open);
      final key = (await tester.runAsync(
        () => f.book(
          'product',
          blocks: 12,
          text: 'Un paragraphe à lire tranquillement. ' * 25,
        ),
      ))!;
      BookReaderController create() => BookReaderController(
        book: Book(
          key: key,
          title: 'Lecture paginée',
          authors: [],
          languages: ['fr'],
        ),
        content: f.content,
        positions: BookPositionRepository(f.db, f.content),
        preferenceStore: BookPreferencesRepository(f.db),
        experienceStore: ExperiencePreferencesRepository(f.db),
        pageIndexStore: PageIndexRepository(f.db),
      );
      var systemScale = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var reader = (await tester.runAsync(() async => create()))!;
      Widget app() => MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(systemScale)),
          child: child!,
        ),
        home: BookReaderScreen(
          book: reader.book,
          content: f.content,
          controller: reader,
        ),
      );
      await runReaderOperation(tester, reader.initialize);
      debugPrint("reader initialized");
      await tester.pumpWidget(app());
      await settleReader(tester, reader);
      debugPrint("reader rendered");
      expect(find.byType(PagedBookView), findsOneWidget);
      expect(find.textContaining(' sur '), findsWidgets);
      for (var n = 0; n < 20; n++) {
        final forward = n % 8 < 4;
        if (n.isEven) {
          await tester.drag(
            find.byType(PageView),
            Offset(forward ? -450 : 450, 0),
          );
        } else {
          final control = find.byTooltip(
            forward ? 'Page suivante' : 'Page précédente',
          );
          await tester.ensureVisible(control);
          await tester.tap(control);
        }
        await settleReader(tester, reader);
        expect(reader.pagination!.retainedPages, lessThanOrEqualTo(3));
      }
      await settleReader(tester, reader, saved: true);
      debugPrint("twenty turns completed");
      final passage = reader.visible!;
      // Exercise the product settings, including cancellation, not only controller methods.
      await tester.tap(find.byTooltip('Réglages de lecture'));
      await waitForReaderControl(tester, find.text('Défilement'));
      await tester.ensureVisible(find.text('Défilement'));
      await tester.tap(find.text('Défilement'));
      await tester.ensureVisible(find.text('Annuler'));
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(reader.experience.mode, ReaderMode.paged);
      await tester.tap(find.byTooltip('Réglages de lecture'));
      await waitForReaderControl(tester, find.text('Défilement'));
      await tester.ensureVisible(find.text('Défilement'));
      await tester.tap(find.text('Défilement'));
      await tester.ensureVisible(find.text('Aéré'));
      await tester.tap(find.text('Aéré'));
      await tester.ensureVisible(find.text('Larges'));
      await tester.tap(find.text('Larges'));
      await tester.ensureVisible(find.text('Appliquer'));
      await tester.tap(find.text('Appliquer'));
      await settleReader(tester, reader);
      expect(reader.experience.mode, ReaderMode.scroll);
      expect(reader.experience.lineHeight, 1.8);
      expect(reader.experience.margins, 28);
      expect(reader.visible!.blockId, passage.blockId);
      expect(reader.visible!.offsetUtf16, passage.offsetUtf16);

      for (var n = 0; n < 10; n++) {
        debugPrint("presentation $n");
        await runReaderOperation(
          tester,
          () => reader.changeExperience(
            ExperiencePreferences(
              mode: n == 3 || n == 7 ? ReaderMode.scroll : ReaderMode.paged,
              lineHeight: [1.2, 1.5, 1.8][n % 3],
              margins: [12.0, 20.0, 28.0][n % 3],
            ),
            readerValue: ReaderPreferences(
              fontScale: n.isEven ? 1 : 1.5,
              theme: n.isEven ? ReaderTheme.light : ReaderTheme.dark,
            ),
          ),
        );
        systemScale = n == 5 ? 3.2 : 1;
        tester.view.physicalSize = n == 4
            ? const Size(844, 390)
            : const Size(390, 844);
        await tester.pumpWidget(app());
        await settleReader(tester, reader);
        expect(reader.visible!.blockId, passage.blockId);
        expect(reader.visible!.offsetUtf16, passage.offsetUtf16);
      }
      await settleReader(tester, reader, saved: true);
      debugPrint("closing reader");
      await tester.pumpWidget(const SizedBox());
      await runReaderOperation(tester, reader.close);
      debugPrint("old reader closed");
      reader = (await tester.runAsync(() async => create()))!;
      debugPrint("new reader created");
      await runReaderOperation(tester, reader.initialize);
      debugPrint("reader initialized");
      expect(reader.visible!.blockId, passage.blockId);
      expect(reader.visible!.offsetUtf16, passage.offsetUtf16);
      await tester.pumpWidget(app());
      await settleReader(tester, reader);
      debugPrint("reader rendered");
      expect(find.byType(PagedBookView), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await runReaderOperation(tester, reader.close);
      await tester.runAsync(f.close);
    },
  );
}
