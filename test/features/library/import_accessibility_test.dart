import 'package:prototype/domain/books.dart';
import 'package:prototype/features/library/library_screen.dart';
import 'package:prototype/features/library/library_controller.dart';
import 'package:prototype/features/library/book_import_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/features/library/import_progress_view.dart';
import 'package:prototype/features/library/book_importer.dart';
import 'package:prototype/infrastructure/database/book_repository.dart'
    show BookSort;

void main() {
  for (final scale in [1.0, 3.2]) {
    testWidgets('progress remains operable at text scale $scale', (
      tester,
    ) async {
      var cancelled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: ImportProgressView(
                progress: const ImportProgress(
                  ImportStep.copying,
                  bytes: 65536,
                ),
                onCancel: () => cancelled = true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Copie du livre'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.text('Annuler')),
        alignment: 0.5,
      );
      await tester.pump();
      await tester.tap(find.text('Annuler'));
      expect(cancelled, true);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('final publication is announced and not cancellable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportProgressView(
            progress: const ImportProgress(ImportStep.finalizing),
            onCancel: () {},
          ),
        ),
      ),
    );
    expect(find.text('Annuler'), findsNothing);
    expect(find.textContaining('Finalisation'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
  testWidgets(
    'empty library, unknown author, cancellation and focus return at large font',
    (tester) async {
      final library = FakeLibrary();
      final job = FakeImport();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(3.2)),
            child: LibraryScreen(
              library: library,
              importController: job,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.textContaining('Votre bibliothèque est vide'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Votre bibliothèque est vide'),
        findsOneWidget,
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1500));
      await tester.pump();
      await Scrollable.ensureVisible(
        tester.element(find.text('Importer un EPUB')),
        alignment: 0.5,
      );
      await tester.pump();
      await tester.tap(find.text('Importer un EPUB'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Choisissez un fichier EPUB'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Choisissez un fichier EPUB'), findsOneWidget);
      await Scrollable.ensureVisible(
        tester.element(find.text('Annuler')),
        alignment: 0.5,
      );
      await tester.pump();
      await tester.tap(find.text('Annuler'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.focusNode!.hasFocus, true);
      await tester.scrollUntilVisible(
        find.text('Import annulé'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Import annulé'), findsOneWidget);
      library.books = [
        Book(
          key: ContentKey(ContentKind.book, 'book', 1),
          title: 'Titre de repli',
          authors: [],
          languages: ['en'],
        ),
      ];
      library.notifyListeners();
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Auteur inconnu'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Auteur inconnu'), findsOneWidget);
      expect(
        find.text('Titre de repli').last,
        findsOneWidget,
      ); // The cover repeats the visible title decoratively.
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a source failure is readable and allows a new explicit selection',
    (tester) async {
      final job = FakeImport()
        ..error = const BookFailure(BookError.sourceUnavailable);
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(
            library: FakeLibrary(),
            importController: job,
            onOpen: (_) {},
          ),
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text(job.error!.message),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(job.error!.message), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1000));
      await tester.pump();
      await Scrollable.ensureVisible(
        tester.element(find.text('Importer un EPUB')),
        alignment: 0.5,
      );
      await tester.pump();
      await tester.tap(find.text('Importer un EPUB'));
      await tester.pump();
      expect(job.running, true);
      expect(tester.takeException(), isNull);
    },
  );
}

class FakeLibrary extends ChangeNotifier implements LibraryController {
  @override
  BookSort sort = BookSort.recent;
  @override
  String searchText = '';
  @override
  final removing = <String>{};
  @override
  final removalErrors = <String, BookFailure>{};
  @override
  List<Book> pendingRemovals = [];
  @override
  String? announcement;
  @override
  get removal => null;
  @override
  bool canOpen(Book book) => true;
  @override
  List<Book> books = [];
  @override
  BookFailure? error;
  @override
  bool loading = false, hasMore = false;
  @override
  Future<void> refresh({String search = '', BookSort? sort}) async {}
  @override
  Future<void> nextPage() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeImport extends ChangeNotifier implements BookImportController {
  @override
  ImportProgress? progress;
  @override
  BookImportResult? result;
  @override
  BookFailure? error;
  @override
  bool running = false;
  @override
  Future<void> start() async {
    running = true;
    progress = const ImportProgress(ImportStep.choosing);
    notifyListeners();
  }

  @override
  Future<void> cancel() async {
    running = false;
    result = const BookImportResult(cancelled: true);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
