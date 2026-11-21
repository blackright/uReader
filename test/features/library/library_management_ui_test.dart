import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/features/library/library_controller.dart';
import 'package:prototype/features/library/library_screen.dart';
import 'package:prototype/features/library/book_removal_service.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';
import 'package:prototype/infrastructure/database/book_operation_repository.dart';
import 'package:prototype/infrastructure/files/book_operation_reconciler.dart';

import '../book_reader/reader_fixture.dart';
import 'import_accessibility_test.dart' show FakeImport;

void main() {
  for (final scale in [1.0, 3.2]) {
    testWidgets(
      'library confirmation, cancellation and focus at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = ReaderFixture();
        await tester.runAsync(f.open);
        addTearDown(f.close);
        await tester.runAsync(() => f.book('ui-book'));
        final repo = BookRepository(f.db),
            journal = BookOperationRepository(f.db);
        final service = BookRemovalService(
          journal: journal,
          files: f.content.files,
          reconciler: BookOperationReconciler(
            repo,
            journal,
            f.content.files,
            purgeAudio: (_) async {},
          ),
          releaseTarget: (_) async {},
        );
        final library = LibraryController(
          repo,
          normalizeKey: (s) async => s,
          removal: service,
        );
        final job = FakeImport();
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: LibraryScreen(
              library: library,
              importController: job,
              onOpen: (_) {},
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
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        }
        expect(library.books, hasLength(1));
        final originalBook = library.books.single;
        await tester.pumpAndSettle();
        final remove = find.byTooltip('Supprimer ui-book');
        await tester.scrollUntilVisible(
          remove,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(remove);
        await tester.pumpAndSettle();
        await tester.runAsync(() => tester.tap(remove));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        expect(await repo.readyPage(), hasLength(1));
        await tester.runAsync(() => tester.tap(remove));
        await tester.pumpAndSettle();
        await tester.runAsync(() => tester.tap(find.text('Supprimer')));
        for (
          var i = 0;
          i < 200 &&
              find
                  .text('Livre supprimé de la bibliothèque.')
                  .evaluate()
                  .isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('Livre supprimé de la bibliothèque.'), findsOneWidget);
        expect(await repo.readyPage(), isEmpty);
        expect(library.canOpen(originalBook), false);
        expect(tester.takeException(), isNull);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Importer un EPUB'),
              )
              .focusNode!
              .hasFocus,
          true,
        );
        await tester.pumpWidget(const SizedBox());
        library.dispose();
        job.dispose();
        await tester.runAsync(service.close);
      },
    );
  }
}
