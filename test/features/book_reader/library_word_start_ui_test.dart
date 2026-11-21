import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app/reader_theme.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/features/book_reader/book_reader_controller.dart';
import 'package:prototype/features/book_reader/book_reader_screen.dart';
import 'package:prototype/features/book_reader/reader_layout.dart';
import 'package:prototype/features/library/library_controller.dart';
import 'package:prototype/features/library/library_screen.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';
import 'package:prototype/infrastructure/database/book_preferences_repository.dart';
import 'package:prototype/infrastructure/database/experience_preferences_repository.dart';
import 'package:prototype/infrastructure/database/page_index_repository.dart';
import 'package:prototype/infrastructure/database/bookmark_repository.dart';

import '../audio_player/player_fixture.dart';
import '../library/import_accessibility_test.dart' show FakeImport;
import 'paged_reader_screen_test.dart'
    show settleReader, runReaderOperation, waitForReaderControl;

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 3.2]) {
      testWidgets(
        'library → exact word → silent cancel → paragraph, dark=$dark scale=$scale',
        (tester) async {
          const capture = bool.fromEnvironment('CAPTURE_PHASE4');
          if (capture) {
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
          }
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final f = PlayerFixture();
          await tester.runAsync(f.open);
          final key = (await tester.runAsync(
            () => f.book(
              'jardin',
              blocks: 2,
              chapters: 1,
              text: 'Avant, 21 pommes. La suite.',
            ),
          ))!;
          final repo = BookRepository(f.db),
              prefs = BookPreferencesRepository(f.db);
          await tester.runAsync(
            () => prefs.save(
              ReaderPreferences(
                theme: dark ? ReaderTheme.dark : ReaderTheme.light,
              ),
            ),
          );
          if (capture) {
            await tester.runAsync(() async {
              await f.db.customStatement(
                "UPDATE books SET title='Les heures tranquilles',authors_json='[\"Camille Martin\"]' WHERE book_id=?",
                [key.id],
              );
              await f.book('rivages', blocks: 1, chapters: 1);
              await f.book('foret', blocks: 1, chapters: 1);
            });
          }
          final book = (await tester.runAsync(() => repo.readyPage()))!
              .firstWhere((book) => book.key == key);
          final reader = (await tester.runAsync(
            () async => BookReaderController(
              book: book,
              content: f.content,
              playback: f.owner,
              preferenceStore: prefs,
              bookmarkStore: BookmarkRepository(f.db, f.content),
              experienceStore: ExperiencePreferencesRepository(
                f.db,
                reader: prefs,
              ),
              pageIndexStore: PageIndexRepository(f.db),
            ),
          ))!;
          final library = (await tester.runAsync(
            () async => LibraryController(repo, normalizeKey: (s) async => s),
          ))!;
          final job = FakeImport();
          final boundary = GlobalKey();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            library.dispose();
            job.dispose();
            await runReaderOperation(tester, reader.close);
            await runReaderOperation(tester, f.close);
          });
          Future<void> save(String name) async {
            if (!capture) return;
            await tester.pump(const Duration(milliseconds: 100));
            final image = (await tester.runAsync(
              () =>
                  (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 2),
            ))!;
            final data = await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.png),
            );
            await tester.runAsync(
              () => File(
                'validation/reader/reports/visual/$name-phase4-${dark ? 'dark' : 'light'}-$scale.png',
              ).writeAsBytes(data!.buffer.asUint8List()),
            );
            image.dispose();
          }

          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ReaderVisualTheme.theme(dark: dark),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Builder(
                  builder: (context) => LibraryScreen(
                    library: library,
                    importController: job,
                    images: f.content,
                    onOpen: (_) => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => BookReaderScreen(
                          book: book,
                          content: f.content,
                          controller: reader,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          for (
            var i = 0;
            i < 200 && (library.loading || library.books.isEmpty);
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 2)),
            );
          }
          await tester.pumpAndSettle();
          final card = find.byKey(ValueKey(key.id));
          await tester.scrollUntilVisible(
            card,
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await save('library');
          await tester.ensureVisible(card);
          await tester.tap(
            find.descendant(of: card, matching: find.byType(InkWell)).first,
          );
          await settleReader(tester, reader);
          expect(f.speech.requests, isEmpty);
          final rich = find
              .descendant(
                of: find.byType(ReaderFragmentView),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is RichText && w.text.toPlainText().contains('Avant,'),
                ),
              )
              .first;
          final render = tester.renderObject<RenderParagraph>(rich);
          final box = render
              .getBoxesForSelection(
                const TextSelection(baseOffset: 7, extentOffset: 9),
              )
              .first
              .toRect();
          await tester.longPressAt(render.localToGlobal(box.center));
          await waitForReaderControl(tester, find.text('Mot sélectionné'));
          expect(find.text('21'), findsOneWidget);
          expect(f.speech.requests, isEmpty);
          await save('word-selection');
          await tester.ensureVisible(find.text('Fermer'));
          await tester.tap(find.text('Fermer'));
          await tester.pumpAndSettle();
          expect(f.speech.requests, isEmpty);
          // Accessible paragraph action opens a bounded list of source words.
          await tester.ensureVisible(find.text('Choisir un paragraphe'));
          await tester.tap(find.text('Choisir un paragraphe'));
          await waitForReaderControl(
            tester,
            find.text('Choisir ce paragraphe'),
          );
          // ContentSeekSheet confirmation uses its explicit button after a passage selection.
          await tester.ensureVisible(find.text('Annuler').last);
          await tester.tap(find.text('Annuler').last);
          await tester.pumpAndSettle();
          // Re-select the shaped word, then explicitly begin; source prefix never reaches synthesis.
          await tester.longPressAt(render.localToGlobal(box.center));
          await waitForReaderControl(tester, find.text('Mot sélectionné'));
          final chooseWord = find.text('Choisir un mot dans ce passage');
          await tester.ensureVisible(chooseWord);
          await tester.tap(chooseWord);
          await waitForReaderControl(tester, find.text('Choisir un mot'));
          final choice = find.byKey(const ValueKey('word-choice-b0-7'));
          await tester.scrollUntilVisible(
            choice,
            180,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.ensureVisible(choice);
          await tester.pumpAndSettle();
          await tester.runAsync(() => tester.tap(choice));
          for (
            var i = 0;
            i < 200 && find.byKey(const ValueKey('word-choice-sheet')).evaluate().isNotEmpty;
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 2)),
            );
          }
          expect(find.byKey(const ValueKey('word-choice-sheet')), findsNothing);
          await tester.pumpAndSettle();
          await waitForReaderControl(tester, find.text('Mot sélectionné'));
          final start = find.text('Commencer à partir d’ici');
          await tester.ensureVisible(start);
          await tester.pumpAndSettle();
          await tester.runAsync(() => tester.tap(start));
          for (var i = 0; i < 200 && f.speech.requests.isEmpty; i++) {
            await tester.pump(const Duration(milliseconds: 20));
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 2)),
            );
          }
          expect(f.speech.requests.first.start.offsetUtf16, 7);
          expect(f.speech.requests.first.text, startsWith('21 pommes'));
          expect(reader.book.key, key);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
