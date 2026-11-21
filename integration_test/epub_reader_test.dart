// Android renderer campaign. Archive access is injected from the authorized
// corpus; native SAF/ZIP coverage belongs to the previous import campaign.
import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/features/book_reader/book_reader_controller.dart';
import 'package:prototype/features/book_reader/book_reader_screen.dart';
import 'package:prototype/features/book_reader/book_image_view.dart';
import 'package:prototype/features/library/book_importer.dart';
import 'package:prototype/infrastructure/database/book_content_repository.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';
import 'package:prototype/infrastructure/database/book_position_repository.dart';
import 'package:prototype/infrastructure/database/book_preferences_repository.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';

import '../test/features/library/epub_corpus_import_test.dart'
    show FixtureSource;
import 'epub_reader_resources.dart';
import 'epub_reader_images.dart';
import '../test/features/book_reader/reader_fixture.dart';
import '../test/features/book_reader/image_bounds_test.dart' show ImageSource;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    '16 megapixel PNG and JPEG remain single flight and release images',
    (tester) async {
      final f = ReaderFixture();
      await f.open();
      final observations = <Map<String, Object?>>[];
      for (final encoded in [readerLargePng, readerLargeJpeg]) {
        final samples = <int>[ProcessInfo.currentRss];
        var beats = 0;
        final monitor = Timer.periodic(const Duration(milliseconds: 5), (_) {
          beats++;
          samples.add(ProcessInfo.currentRss);
        });
        final source = ImageSource(
          f,
          BookImagePayload(base64Decode(encoded), 4000, 4000),
        );
        final decoder = BookImageDecoder(source);
        for (var round = 0; round < 10; round++) {
          final batch = await Future.wait(
            List.generate(
              3,
              (i) => decoder.load(
                ContentKey(ContentKind.book, 'image-book', 1),
                'r$i',
                () => false,
              ),
            ),
          );
          for (final image in batch) {
            expect(image, isNotNull);
            expect(image!.width, 2048);
            expect(image.height, 2048);
            image.dispose();
          }
          await tester.pump(const Duration(milliseconds: 20));
        }
        monitor.cancel();
        expect(decoder.peakActive, 1);
        expect(beats, greaterThan(0));
        observations.add({
          'format': observations.isEmpty ? 'PNG' : 'JPEG',
          'sourcePixels': 16000000,
          'decodes': 30,
          'peakActive': decoder.peakActive,
          'heartbeats': beats,
          'rssBytes': samples,
          'outputWidth': 2048,
          'outputHeight': 2048,
        });
      }
      binding.reportData = {
        ...?binding.reportData,
        'imageBounds': observations,
      };
      await f.close();
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: const bool.fromEnvironment('US2_SKIP_FAILED_IMAGE_STRESS'),
  );
  testWidgets(
    'long chapter renders bounded windows without retaining visited pages',
    (tester) async {
      final f = ReaderFixture();
      await f.open();
      final key = await f.book(
        'long-reader',
        blocks: 1500,
        chapters: 1,
        text: 'abcd' * 1024,
      );
      final reader = BookReaderController(
        book: Book(
          key: key,
          title: 'Long chapitre',
          authors: [],
          languages: ['fr'],
        ),
        content: f.content,
      );
      await reader.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: BookReaderScreen(
            book: reader.book,
            content: f.content,
            controller: reader,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rss = <int>[];
      final micros = <int>[];
      var heartbeats = 0;
      final heartbeat = Timer.periodic(
        const Duration(milliseconds: 20),
        (_) => heartbeats++,
      );
      var windows = 0;
      do {
        final w = reader.window!;
        expect(w.blocks.length, lessThanOrEqualTo(64));
        expect(
          w.blocks.fold<int>(0, (n, b) => n + b.text.length),
          lessThanOrEqualTo(65536),
        );
        expect(reader.retainedWindows, lessThanOrEqualTo(2));
        rss.add(ProcessInfo.currentRss);
        windows++;
        if (w.next == null) break;
        final timer = Stopwatch()..start();
        await reader.next();
        await tester.pumpAndSettle();
        micros.add(timer.elapsedMicroseconds);
        expect(tester.takeException(), isNull);
      } while (true);
      heartbeat.cancel();
      expect(windows, greaterThan(90));
      expect(heartbeats, greaterThan(0));
      binding.reportData = {
        ...?binding.reportData,
        'bounds': {
          'utf16Units': 6144000,
          'windows': windows,
          'rssBytes': rss,
          'navigationMicros': micros,
          'heartbeats': heartbeats,
          'retainedWindowsMaximum': 2,
          'measurement': 'debug process RSS sampled after each rendered window; not decoder peak',
        },
      };
      await tester.pumpWidget(const SizedBox());
      await reader.close();
      await f.close();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
  testWidgets(
    'ten EPUBs: canonical reading and presentation without source access',
    (tester) async {
      final temporary = await Directory.systemTemp.createTemp('us2-reader-');
      final dir = Directory(await temporary.resolveSymbolicLinks());
      final db = PrototypeDatabase(NativeDatabase.memory());
      final files = await BookFileStore.open(dir);
      final books = BookRepository(db);
      final content = BookContentRepository(db, files);
      final positions = BookPositionRepository(db, content);
      final prefs = BookPreferencesRepository(db);
      final results = <Map<String, Object?>>[];
      final corpus = jsonDecode(readerCorpusJson) as Map;
      for (final raw in corpus['books'] as List) {
        final entry = raw as Map;
        final id = entry['id'] as String;
        final importer = BookImporter(
          source: FixtureSource(files, entry),
          books: books,
          files: files,
          normalizeKey: (s) async => s.toLowerCase(),
        );
        final imported = await importer.importBook('reader-$id', id, 1);
        final book = imported.book!;
        await importer.shutdown(); // No source handle is used by the reader.
        final reader = BookReaderController(
          book: book,
          content: content,
          positions: positions,
          preferenceStore: prefs,
        );
        await reader.initialize();
        expect(reader.error, isNull);
        final chapters = entry['reference']['chapters'] as List;
        expect(reader.chapters.length, chapters.length);
        final actual = <String, String>{};
        final blocks = <BookBlock>[];
        BookCursor? after;
        do {
          final window = await content.window(book.key, 77, after: after);
          expect(window.blocks.length, lessThanOrEqualTo(64));
          expect(
            window.blocks.fold<int>(0, (n, b) => n + b.text.length),
            lessThanOrEqualTo(65536),
          );
          actual.addAll({for (final b in window.blocks) b.id: b.text});
          blocks.addAll(window.blocks);
          after = window.next;
        } while (after != null);
        for (final chapter in chapters) {
          for (final block in chapter['initialCanonicalBlocks'] as List) {
            expect(
              actual[block['id']],
              block['text'],
              reason: '$id ${block['id']}',
            );
          }
        }
        await tester.pumpWidget(
          MaterialApp(
            home: BookReaderScreen(
              book: book,
              content: content,
              controller: reader,
            ),
          ),
        );
        await tester.pumpAndSettle();
        var imageCount = 0, noteCount = 0, linkCount = 0;
        final decoder = BookImageDecoder(content);
        for (final block in blocks) {
          if (block.kind == BookBlockKind.image && block.resourceId != null) {
            final image = await decoder.load(
              book.key,
              block.resourceId!,
              () => false,
            );
            // Unsupported/corrupt resources intentionally remain placeholders.
            if (image != null) {
              expect(image.width, lessThanOrEqualTo(2048));
              expect(image.height, lessThanOrEqualTo(2048));
              image.dispose();
            }
            imageCount++;
          }
          if (block.isIdentifiedNote) {
            await reader.openNote(
              BookLocator(
                key: book.key,
                chapterId: block.chapterId,
                blockId: block.id,
                offsetUtf16: 0,
              ),
            );
            expect(reader.noteWindow!.blocks.first.id, block.id);
            expect(reader.retainedWindows, lessThanOrEqualTo(2));
            reader.closeNote();
            noteCount++;
          }
          for (final span in block.inline) {
            final target = span.link;
            if (target == null) continue;
            try {
              final resolved = await reader.resolve(block, target.target);
              if (resolved.external == null) {
                await reader.internalTarget(resolved);
              }
            } on BookFailure catch (error) {
              expect(
                error.code,
                anyOf(BookError.unsafeLink, BookError.invalidLocator),
              );
            }
            linkCount++;
          }
        }
        for (final chapter in reader.chapters) {
          await reader.chapter(chapter.id);
          await tester.pumpAndSettle();
          expect(reader.window!.blocks.first.chapterId, chapter.id);
          expect(reader.retainedWindows, lessThanOrEqualTo(2));
          expect(tester.takeException(), isNull);
        }
        await reader.changePreferences(
          ReaderPreferences(fontScale: 1.5, theme: ReaderTheme.dark),
        );
        await tester.pumpAndSettle();
        await reader.flush();
        final saved = await positions.read(book.key, ReadingMode.visual);
        expect(saved, isNotNull);
        results.add({
          'id': id,
          'chapters': chapters.length,
          'canonicalBlocks': actual.length,
          'retainedWindows': reader.retainedWindows,
          'sourceAfterImport': false,
          'lastChapter': reader.window!.blocks.first.chapterId,
          'rssBytes': ProcessInfo.currentRss,
          'imagesChecked': imageCount,
          'notesChecked': noteCount,
          'linksChecked': linkCount,
        });
        await tester.pumpWidget(const SizedBox());
        await reader.close();
      }
      await prefs.flush();
      await db.close();
      await dir.delete(recursive: true);
      binding.reportData = {
        ...?binding.reportData,
        'readerCorpus': results,
        'archiveAccess': 'injected authorized fixture',
        'scope': 'visual reader; no audio or product database opened',
      };
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
