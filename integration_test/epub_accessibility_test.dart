// Automated semantics/large-text paths. Manual TalkBack remains a separate gate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/features/library/library_controller.dart';
import 'package:prototype/features/library/library_screen.dart';
import 'package:prototype/features/library/book_importer.dart';
import 'package:prototype/features/library/book_import_controller.dart';
import 'package:prototype/features/book_reader/book_reader_screen.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';

import '../test/features/library/epub_corpus_import_test.dart'
    show FixtureSource;
import 'epub_management_harness.dart';
import 'feasibility_bootstrap.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'US4 import/open/search/sort/delete semantic actions at normal and large scale',
    (tester) async {
      await waitForNative(tester);
      final semantics = tester.ensureSemantics();
      final results = <Map<String, Object?>>[];
      try {
        for (final scale in [1.0, 3.2]) {
          final h = EpubManagementHarness();
          await h.open();
          final importer = BookImporter(
            source: FixtureSource(h.bookFiles, h.corpus.first as Map),
            books: h.books,
            files: h.bookFiles,
            normalizeKey: h.normalizer.normalize,
          );
          final job = BookImportController(importer),
              library = LibraryController(
                h.books,
                normalizeKey: h.normalizer.normalize,
                removal: h.removal,
              );
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => LibraryScreen(
                  library: library,
                  importController: job,
                  onOpen: (book) => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          BookReaderScreen(book: book, content: h.content),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Importer un EPUB'));
          for (
            var i = 0;
            i < 500 && (job.running || library.books.isEmpty);
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 20));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(job.error, isNull);
          expect(library.books, hasLength(1));
          await tester.pumpAndSettle();
          final book = library.books.single;
          await tester.scrollUntilVisible(
            find.text(book.title),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(book.title));
          await tester.pumpAndSettle();
          expect(find.byTooltip('Sommaire'), findsOneWidget);
          await tester.tap(find.byTooltip('Sommaire'));
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Réglages de lecture'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Annuler'),
            150,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Annuler'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Retour'));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byType(TextField),
            -150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField),
            book.title.toUpperCase(),
          );
          await tester.testTextInput.receiveAction(TextInputAction.done);
          FocusManager.instance.primaryFocus?.unfocus();
          for (var i = 0; i < 300 && library.loading; i++) {
            await tester.pump(const Duration(milliseconds: 20));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await tester.pumpAndSettle();
          await tester.tap(find.byType(DropdownButtonFormField<BookSort>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Auteur').last);
          for (var i = 0; i < 300 && library.loading; i++) {
            await tester.pump(const Duration(milliseconds: 20));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await tester.pumpAndSettle();
          expect(library.searchText, book.title.toUpperCase());
          expect(library.sort, BookSort.author);
          expect(library.books, hasLength(1));
          final remove = find.byTooltip('Supprimer ${book.title}');
          await tester.scrollUntilVisible(
            remove,
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(remove);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Annuler'));
          await tester.pumpAndSettle();
          expect(await h.books.readyPage(), hasLength(1));
          await tester.tap(remove);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Supprimer'));
          for (
            var i = 0;
            i < 300 &&
                find
                    .text('Livre supprimé de la bibliothèque.')
                    .evaluate()
                    .isEmpty;
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 20));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          await tester.pumpAndSettle();
          expect(
            find.text('Livre supprimé de la bibliothèque.'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          results.add({
            'scale': scale,
            'import': 'injected authorized source',
            'openReader': true,
            'toc': true,
            'settingsCancel': true,
            'searchSort': true,
            'cancelDeletion': true,
            'confirmedDeletion': true,
            'talkBack': 'not_evaluated',
            'audioControls': 'not_evaluated in this isolated visual campaign',
          });
          await tester.pumpWidget(const SizedBox());
          job.dispose();
          library.dispose();
          await importer.shutdown();
          await h.close();
        }
        binding.reportData = {
          'accessibilityAutomation': results,
          'maximumPhysicalFontSetting':
              'not_measured; simulated text scale only',
        };
      } finally {
        semantics.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
