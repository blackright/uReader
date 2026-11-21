import 'dart:async';
// Physical visual-reader campaign; synthetic EPUBs and isolated database only.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:prototype/infrastructure/database/book_content_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/pagination.dart';
import 'package:prototype/domain/reader_experience.dart';
import 'package:prototype/features/book_reader/book_reader_controller.dart';
import 'package:prototype/features/book_reader/book_reader_screen.dart';
import 'package:prototype/features/book_reader/paged_book_view.dart';
import 'package:prototype/infrastructure/database/book_position_repository.dart';
import 'package:prototype/infrastructure/database/book_preferences_repository.dart';
import 'package:prototype/infrastructure/database/experience_preferences_repository.dart';
import 'package:prototype/infrastructure/database/page_index_repository.dart';

import 'epub_management_harness.dart';
import 'feasibility_bootstrap.dart';
import '../test/features/book_reader/paged_reader_screen_test.dart'
    show settleReader, runReaderOperation;

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

/// Returns a real DB window late, so stale-result rejection is exercised on
/// device rather than inferred from sequential presentation changes.
class _GatedReaderSource extends BookContentRepository {
  _GatedReaderSource(super.db, super.files);
  int? heldGeneration, replacementGeneration;
  final readHeld = Completer<void>(), releaseRead = Completer<void>();
  bool heldOnce = false,
      oldResultReturned = false,
      replacementReadStarted = false;
  @override
  Future<BookWindow> window(
    ContentKey key,
    int generation, {
    BookCursor? after,
    int maxBlocks = 64,
    int maxUnits = 65536,
  }) async {
    if (generation == replacementGeneration) replacementReadStarted = true;
    final result = await super.window(
      key,
      generation,
      after: after,
      maxBlocks: maxBlocks,
      maxUnits: maxUnits,
    );
    if (!heldOnce && generation == heldGeneration && after?.nextOrdinal == 0) {
      heldOnce = true;
      readHeld.complete();
      await releaseRead.future;
      oldResultReturned = true;
    }
    return result;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('immersive reader: whole corpus, turns, presentation and reopen', (
    tester,
  ) async {
    await waitForNative(tester);
    final h = EpubManagementHarness();
    await tester.runAsync(() => h.open());
    final rows = <Map<String, Object?>>[];
    final changes = <Map<String, Object?>>[];
    final replacementProofs = <Map<String, Object?>>[];
    BookReaderController? active;
    try {
      for (var i = 0; i < 10; i++) {
        final book = (await tester.runAsync(() => h.importAt(i)))!;
        final preferences = BookPreferencesRepository(h.db);
        final source = i == 8
            ? _GatedReaderSource(h.db, h.bookFiles)
            : h.content;
        BookReaderController create() => BookReaderController(
          book: book,
          content: source,
          positions: BookPositionRepository(h.db, source),
          preferenceStore: preferences,
          experienceStore: ExperiencePreferencesRepository(
            h.db,
            reader: preferences,
          ),
          pageIndexStore: PageIndexRepository(h.db),
        );
        active = (await tester.runAsync(() async => create()))!;
        await runReaderOperation(tester, active.initialize);
        await tester.pumpWidget(
          MaterialApp(
            home: BookReaderScreen(
              book: book,
              content: source,
              controller: active,
            ),
          ),
        );
        await settleReader(tester, active);
        final reader = active;
        final pager = reader.pagination!;
        expect(find.byType(PagedBookView), findsOneWidget);
        expect(pager.pageNumber, 1);
        final expected = await tester.runAsync(() async {
          Stream<List<int>> text() async* {
            BookCursor? cursor;
            do {
              final window = await h.content.window(
                book.key,
                1,
                after: cursor,
                maxBlocks: 1,
              );
              for (final block in window.blocks) {
                yield utf8.encode(block.text);
              }
              cursor = window.next;
            } while (cursor != null);
          }

          return sha256.bind(text()).first;
        });
        final sink = _DigestSink();
        final hash = sha256.startChunkedConversion(sink);
        var point = PagePoint(0, 0), visited = 0, gestures = 0, commands = 0;
        final latencies = <int>[];
        final watch = Stopwatch()..start();
        while (true) {
          final page = pager.current!;
          expect(page.start, point);
          point = page.end;
          for (final fragment in page.fragments) {
            hash.add(
              utf8.encode(
                fragment.block.text.substring(
                  fragment.startUtf16,
                  fragment.endUtf16,
                ),
              ),
            );
          }
          visited++;
          expect(pager.retainedPages, lessThanOrEqualTo(3));
          expect(reader.retainedWindows, lessThanOrEqualTo(2));
          if (pager.next == null) break;
          final turn = Stopwatch()..start();
          if (i == 8 && visited <= 20 && visited.isOdd) {
            await tester.drag(find.byType(PageView), const Offset(-300, 0));
            gestures++;
          } else {
            final button = find.byTooltip('Page suivante');
            await tester.ensureVisible(button);
            await tester.tap(button);
            commands++;
          }
          await settleReader(tester, reader, saved: true);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'Passage paginé',
          );
          latencies.add(turn.elapsedMicroseconds);
          expect(pager.current!.start, point);
          if (visited > 10000) fail('Unexpected page count');
        }
        hash.close();
        expect(sink.value, expected);
        expect(visited, pager.total);
        if (i == 8) {
          expect(gestures, 10);
          final chapter = reader.chapters.reduce(
            (a, b) => a.textUnits >= b.textUnits ? a : b,
          );
          expect(chapter.blockCount, greaterThan(64));
          final middle = (await tester.runAsync(
            () => h.content.window(
              book.key,
              1,
              after: BookCursor(
                key: book.key,
                generation: 1,
                nextOrdinal:
                    chapter.firstBlockOrdinal + chapter.blockCount ~/ 2,
              ),
              maxBlocks: 1,
            ),
          ))!.blocks.single;
          await runReaderOperation(
            tester,
            () => reader.go(
              BookLocator(
                key: book.key,
                chapterId: middle.chapterId,
                blockId: middle.id,
                offsetUtf16: 0,
              ),
            ),
          );
          await settleReader(tester, reader, saved: true);
          final target = reader.visible!;
          for (var n = 0; n < 10; n++) {
            final change = Stopwatch()..start();
            await runReaderOperation(
              tester,
              () => reader.changeExperience(
                ExperiencePreferences(
                  mode: n == 3 || n == 7 ? ReaderMode.scroll : ReaderMode.paged,
                  margins: [12.0, 20.0, 28.0][n % 3],
                  lineHeight: [1.2, 1.5, 1.8][n % 3],
                ),
                readerValue: ReaderPreferences(
                  fontScale: n.isEven ? 1 : 1.5,
                  theme: n.isEven ? ReaderTheme.light : ReaderTheme.dark,
                ),
              ),
            );
            if (n == 4 || n == 5) {
              await SystemChrome.setPreferredOrientations(
                n == 4
                    ? [DeviceOrientation.landscapeLeft]
                    : [DeviceOrientation.portraitUp],
              );
            }
            await settleReader(tester, reader);
            expect(reader.visible!.blockId, target.blockId);
            expect(reader.visible!.offsetUtf16, target.offsetUtf16);
            expect(pager.retainedPages, lessThanOrEqualTo(3));
            expect(reader.retainedWindows, lessThanOrEqualTo(2));
            final cache = await tester.runAsync(
              () => h.db
                  .customSelect(
                    'SELECT COUNT(*) AS n FROM book_page_runs WHERE book_id=?',
                    variables: [Variable(book.key.id)],
                  )
                  .getSingle(),
            );
            expect(cache!.read<int>('n'), lessThanOrEqualTo(1));
            final view = tester.view;
            changes.add({
              'change': n,
              'micros': change.elapsedMicroseconds,
              'rssBytes': ProcessInfo.currentRss,
              'widthPixels': view.physicalSize.width,
              'heightPixels': view.physicalSize.height,
              'mode': reader.experience.mode.name,
              'chapter': target.chapterId,
              'block': target.blockId,
              'chapterBlocks': chapter.blockCount,
              'retainedPages': pager.retainedPages,
              'retainedWindows': reader.retainedWindows,
              'indexRuns': cache.read<int>('n'),
            });
          }
          final gated = source as _GatedReaderSource;
          final layout = pager.layout!;
          final started = Stopwatch()..start();
          var stalePublished = false, waitingForNewRead = false;
          void observe() {
            if (waitingForNewRead &&
                !gated.replacementReadStarted &&
                pager.current != null) {
              stalePublished = true;
            }
          }

          pager.addListener(observe);
          try {
            gated.heldGeneration = pager.generation + 1;
            await runReaderOperation(
              tester,
              () => pager.configure(layout, target),
            );
            await runReaderOperation(tester, () => gated.readHeld.future);
            final oldGeneration = pager.generation;
            gated.replacementGeneration = oldGeneration + 1;
            waitingForNewRead = true;
            final replacement = pager.configure(layout, target);
            expect(pager.generation, oldGeneration + 1);
            gated.releaseRead.complete();
            await runReaderOperation(tester, () => replacement);
            await settleReader(tester, reader);
            waitingForNewRead = false;
            expect(gated.oldResultReturned, isTrue);
            expect(gated.replacementReadStarted, isTrue);
            expect(stalePublished, isFalse);
            expect(pager.error, isNull);
            expect(reader.visible!.blockId, target.blockId);
            expect(reader.visible!.offsetUtf16, target.offsetUtf16);
            final run = await tester.runAsync(
              () => h.db
                  .customSelect(
                    'SELECT generation,state FROM book_page_runs WHERE book_id=?',
                    variables: [Variable(book.key.id)],
                  )
                  .get(),
            );
            expect(run!.length, 1);
            expect(run.single.read<int>('generation'), pager.generation);
            expect(run.single.read<String>('state'), 'ready');
            replacementProofs.add({
              'book': book.key.id,
              'heldGeneration': oldGeneration,
              'replacementGeneration': pager.generation,
              'oldResultReturned': true,
              'stalePublished': stalePublished,
              'indexCurrentGeneration': true,
              'samePassage': true,
              'micros': started.elapsedMicroseconds,
              'retainedPages': pager.retainedPages,
              'retainedWindows': reader.retainedWindows,
              'rssBytes': ProcessInfo.currentRss,
            });
          } finally {
            waitingForNewRead = false;
            pager.removeListener(observe);
            if (!gated.releaseRead.isCompleted) gated.releaseRead.complete();
          }
        }
        final position = reader.visible!;
        await tester.pumpWidget(const SizedBox());
        await runReaderOperation(tester, reader.close);
        active = (await tester.runAsync(() async => create()))!;
        await runReaderOperation(tester, active.initialize);
        expect(active.visible!.blockId, position.blockId);
        expect(active.visible!.offsetUtf16, position.offsetUtf16);
        await runReaderOperation(tester, active.close);
        active = null;
        rows.add({
          'book': book.key.id,
          'pagesVisited': visited,
          'gestures': gestures,
          'buttonTurns': commands,
          'turnMicros': latencies,
          'elapsedMicros': watch.elapsedMicroseconds,
          'rssBytes': ProcessInfo.currentRss,
          'sourceHashMatches': true,
          'widgetReopen': true,
        });
        binding.reportData = {
          'visualReader': rows,
          'presentationChanges': changes,
          'replacementProofs': replacementProofs,
          'productDatabaseOpened': false,
          'audioOwnerCreated': false,
          'screenReader': 'not_evaluated',
          'physicalProcessRestarts': 'not_evaluated',
        };
      }
      binding.reportData!['databaseBytes'] = await File(
        '${h.root.path}/library.sqlite',
      ).length();
    } finally {
      await tester.pumpWidget(const SizedBox());
      if (active != null) await runReaderOperation(tester, active.close);
      await SystemChrome.setPreferredOrientations([]);
      await tester.runAsync(h.close);
    }
  });
}
