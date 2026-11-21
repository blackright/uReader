// Real widgets, synthetic book and bookmarks only. Not an Android/TalkBack acceptance.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/features/book_reader/book_reader_controller.dart';
import 'package:prototype/features/book_reader/book_reader_screen.dart';
import 'package:prototype/features/book_reader/bookmarks_sheet.dart';
import 'package:prototype/features/book_reader/reader_layout.dart';
import 'package:prototype/infrastructure/database/bookmark_repository.dart';
import 'package:prototype/infrastructure/database/book_preferences_repository.dart';
import 'package:prototype/infrastructure/database/experience_preferences_repository.dart';
import 'package:prototype/infrastructure/database/page_index_repository.dart';

import '../../../test/features/book_reader/reader_fixture.dart';
import '../../../test/features/book_reader/paged_reader_screen_test.dart'
    show settleReader, runReaderOperation, waitForReaderControl;

void main() {
  testWidgets('capture implemented bookmarks using a synthetic book', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final entry in {
        'Roboto': 'C:/dev/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
        'MaterialIcons': 'C:/dev/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        'serif': 'C:/Windows/Fonts/georgia.ttf',
      }.entries) {
        final file = File(entry.value);
        if (await file.exists()) {
          await (FontLoader(entry.key)..addFont(
                file.readAsBytes().then((b) => ByteData.sublistView(b)),
              ))
              .load();
        }
      }
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = ReaderFixture();
    await tester.runAsync(f.open);
    final store = (await tester.runAsync(
      () async => BookmarkRepository(f.db, f.content),
    ))!;
    for (final theme in ReaderTheme.values) {
      final key = (await tester.runAsync(
        () => f.book(
          'visual-bookmarks-${theme.name}',
          text: 'Chaque matin, Léa ouvre la petite porte du jardin. La lumière traverse les feuilles et dessine des ombres sur le chemin.',
        ),
      ))!;
      final prefs = (await tester.runAsync(
        () async => BookPreferencesRepository(f.db),
      ))!;
      await tester.runAsync(() => prefs.save(ReaderPreferences(theme: theme)));
      final reader = (await tester.runAsync(
        () async => BookReaderController(
          book: Book(
            key: key,
            title: 'Les heures tranquilles',
            authors: ['Camille Martin'],
            languages: ['fr'],
          ),
          content: f.content,
          bookmarkStore: store,
          preferenceStore: prefs,
          experienceStore: ExperiencePreferencesRepository(f.db, reader: prefs),
          pageIndexStore: PageIndexRepository(f.db),
        ),
      ))!;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: BookReaderScreen(
              book: reader.book,
              content: f.content,
              controller: reader,
            ),
          ),
        ),
      );
      await settleReader(tester, reader);
      Future<void> save(String name) async {
        await tester.pump(const Duration(milliseconds: 100));
        final image = (await tester.runAsync(
          () =>
              (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2),
        ))!;
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.png),
        );
        await tester.runAsync(
          () => File(
            'validation/reader/reports/visual/$name-phase3-${theme.name}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List()),
        );
        image.dispose();
      }

      Future<void> showMarks() async {
        await tester.tap(find.byTooltip('Signets'));
        await waitForReaderControl(tester, find.text('Mes passages'));
        final model = tester
            .widget<BookmarksSheet>(find.byType(BookmarksSheet))
            .controller;
        for (var i = 0; i < 200 && model.busy; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        expect(model.error, isNull);
        await tester.pumpAndSettle();
      }

      await save('reader-bookmarks');
      await showMarks();
      await save('bookmarks-empty');
      await tester.ensureVisible(find.text('Fermer les signets'));
      await tester.tap(find.text('Fermer les signets'));
      await tester.pumpAndSettle();
      for (final n in [0, 2, 4]) {
        await tester.runAsync(
          () => store.add(
            BookLocator(
              key: key,
              chapterId: n < 4 ? 'c0' : 'c1',
              blockId: 'b$n',
              offsetUtf16: 0,
            ),
          ),
        );
      }
      await showMarks();
      await save('bookmarks-list');
      await tester.ensureVisible(find.text('Fermer les signets'));
      await tester.tap(find.text('Fermer les signets'));
      await tester.pumpAndSettle();
      await tester.longPress(
        find.byType(ReaderFragmentView).hitTestable().first,
      );
      await waitForReaderControl(tester, find.text('Paragraphe sélectionné'));
      await save('bookmark-paragraph');
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await runReaderOperation(tester, reader.close);
    }
    await tester.runAsync(store.flush);
    await tester.runAsync(f.close);
  });
}
