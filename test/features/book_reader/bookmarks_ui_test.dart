import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/features/book_reader/book_reader_controller.dart';
import 'package:prototype/features/book_reader/book_reader_screen.dart';
import 'package:prototype/features/book_reader/reader_layout.dart';
import 'package:prototype/features/book_reader/bookmarks_sheet.dart';
import 'package:prototype/infrastructure/database/bookmark_repository.dart';
import 'package:prototype/infrastructure/database/book_preferences_repository.dart';
import 'package:prototype/infrastructure/database/experience_preferences_repository.dart';
import 'package:prototype/infrastructure/database/page_index_repository.dart';

import '../audio_player/player_fixture.dart';
import 'paged_reader_screen_test.dart'
    show settleReader, runReaderOperation, waitForReaderControl;

void main() {
  for (final scale in [1.0, 3.2]) {
    testWidgets('add/open/remove and paragraph bookmark, scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = PlayerFixture();
      await tester.runAsync(f.open);
      final key = (await tester.runAsync(
        () => f.book(
          'bookmark-ui',
          text: 'Une page de jardin et de lumière. ' * 10,
        ),
      ))!;
      final store = (await tester.runAsync(
        () async => BookmarkRepository(f.db, f.content),
      ))!;
      BookLocator at(int i) => BookLocator(
        key: key,
        chapterId: i < 4 ? 'c0' : 'c1',
        blockId: 'b$i',
        offsetUtf16: 0,
      );
      await tester.runAsync(() => store.add(at(1)));
      await tester.runAsync(() => store.add(at(4)));
      final prefs = (await tester.runAsync(
        () async => BookPreferencesRepository(f.db),
      ))!;
      await tester.runAsync(
        () => prefs.save(
          ReaderPreferences(
            theme: scale == 1 ? ReaderTheme.light : ReaderTheme.dark,
          ),
        ),
      );
      final reader = (await tester.runAsync(
        () async => BookReaderController(
          book: Book(
            key: key,
            title: 'Le jardin',
            authors: [],
            languages: ['fr'],
          ),
          content: f.content,
          playback: f.owner,
          bookmarkStore: store,
          preferenceStore: prefs,
          experienceStore: ExperiencePreferencesRepository(f.db, reader: prefs),
          pageIndexStore: PageIndexRepository(f.db),
        ),
      ))!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await runReaderOperation(tester, reader.close);
        await tester.runAsync(f.close);
      });
      await tester.runAsync(
        () => f.owner.playFromParagraph(f.context(key), at(0)),
      );
      await tester.runAsync(f.owner.pause);
      final generation = f.owner.sessionGeneration,
          requests = f.speech.requests.length;
      await tester.pumpWidget(
        MaterialApp(
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: BookReaderScreen(
            book: reader.book,
            content: f.content,
            controller: reader,
          ),
        ),
      );
      await settleReader(tester, reader);
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
        expect(model.entries, isNotEmpty);
        await tester.pumpAndSettle();
      }

      Future<Finder> reveal(String prefix) async {
        final model = tester
            .widget<BookmarksSheet>(find.byType(BookmarksSheet))
            .controller;
        final control = find.byKey(
          ValueKey('$prefix-${model.entries.first.bookmark.id}'),
        );
        final list = find.descendant(
          of: find.byType(BookmarksSheet),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(control, 250, scrollable: list);
        await tester.pumpAndSettle();
        return control;
      }

      await showMarks();
      await tester.ensureVisible(
        find.text('Ajouter un signet au passage visible'),
      );
      await tester.tap(find.text('Ajouter un signet au passage visible'));
      await waitForReaderControl(tester, find.text('Signet ajouté.'));
      expect((await tester.runAsync(() => store.list(key)))!.items.length, 3);
      final first = await reveal('bookmark');
      await tester.ensureVisible(first);
      await tester.tap(first);
      for (
        var i = 0;
        i < 200 && find.text('Mes passages').evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await settleReader(tester, reader);
      expect(reader.focusLocator!.blockId, 'b1');
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'Passage paginé');
      await showMarks();
      final remove = await reveal('bookmark-remove');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await waitForReaderControl(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.liveRegion == true &&
              w.properties.label == 'Signet supprimé.',
        ),
      );
      expect((await tester.runAsync(() => store.list(key)))!.items.length, 2);
      await tester.scrollUntilVisible(
        find.text('Fermer les signets'),
        250,
        scrollable: find.descendant(
          of: find.byType(BookmarksSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Fermer les signets'));
      await tester.pumpAndSettle();
      await tester.longPress(
        find.byType(ReaderFragmentView).hitTestable().first,
      );
      await waitForReaderControl(tester, find.text('Paragraphe sélectionné'));
      await tester.ensureVisible(find.text('Ajouter un signet ici'));
      await tester.tap(find.text('Ajouter un signet ici'));
      for (
        var i = 0;
        i < 200 &&
            find.text('Signet ajouté.').evaluate().isEmpty &&
            find.text('Ce passage possède déjà un signet.').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      expect(
        find.text('Signet ajouté.').evaluate().isNotEmpty ||
            find
                .text('Ce passage possède déjà un signet.')
                .evaluate()
                .isNotEmpty,
        isTrue,
      );
      expect(f.owner.sessionGeneration, generation);
      expect(f.speech.requests.length, requests);
      expect(f.player.opens, 0);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Fermer'));
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
    });
  }
}
