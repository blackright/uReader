// 003 paginated reader: six distinct Android processes, isolated database only.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prototype/domain/reader_experience.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/features/book_reader/book_reader_controller.dart';
import 'package:prototype/features/book_reader/book_reader_screen.dart';
import 'package:prototype/features/library/book_importer.dart';
import 'package:prototype/infrastructure/database/book_content_repository.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';
import 'package:prototype/infrastructure/database/book_position_repository.dart';
import 'package:prototype/infrastructure/database/book_preferences_repository.dart';
import 'package:prototype/infrastructure/database/experience_preferences_repository.dart';
import 'package:prototype/infrastructure/database/page_index_repository.dart';

import '../test/features/book_reader/paged_reader_screen_test.dart'
    show settleReader, runReaderOperation;

import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';

import '../test/features/library/epub_corpus_import_test.dart'
    show FixtureSource;
import 'epub_reader_resources.dart';
import 'feasibility_bootstrap.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('paged visual checkpoint survives a fresh Android process', (
    tester,
  ) async {
    await waitForNative(tester);
    final support = Directory(
      await (await getApplicationSupportDirectory()).resolveSymbolicLinks(),
    );
    final root = Directory('${support.path}/us1-paged-resume-20261119');
    await root.create(recursive: true);
    final marker = File('${root.path}/checkpoint.json');
    final state = await marker.exists()
        ? jsonDecode(await marker.readAsString()) as Map
        : <String, dynamic>{'step': 0};
    final step = state['step'] as int;
    expect(
      step,
      lessThanOrEqualTo(5),
      reason: 'Dedicated campaign already complete; preserve its evidence.',
    );
    final db = PrototypeDatabase(
      NativeDatabase(File('${root.path}/reader.sqlite')),
    );
    await db.initialize();
    final books = BookRepository(db);
    final files = await BookFileStore.open(root);
    final content = BookContentRepository(db, files);
    final positions = BookPositionRepository(db, content);
    final prefs = BookPreferencesRepository(db);
    if (step == 0) {
      final corpus = jsonDecode(readerCorpusJson) as Map;
      for (final entry in (corpus['books'] as List).take(3)) {
        final importer = BookImporter(
          source: FixtureSource(files, entry as Map),
          books: books,
          files: files,
          normalizeKey: (s) async => s.toLowerCase(),
        );
        final result = await importer.importBook(
          'resume-${entry['id']}',
          entry['id'] as String,
          1,
        );
        final first = (await content.window(result.book!.key, 1)).blocks.first;
        await db.customStatement(
          "INSERT INTO book_positions VALUES (?,'audio',?,?,?,?,17,123)",
          [result.book!.key.id, 1, first.chapterId, first.id, 0],
        );
        await importer.shutdown();
      }
    }
    final all = [...await books.readyPage()]
      ..sort((a, b) => a.key.id.compareTo(b.key.id));
    expect(all.length, 3);
    final audio =
        (await db
                .customSelect(
                  "SELECT * FROM book_positions WHERE mode='audio' ORDER BY book_id",
                )
                .get())
            .map((r) => r.data)
            .toList();
    var physicalGestures = 0;
    Map<String, Object?>? presentationProof;
    if (step > 0) {
      expect(
        pid,
        isNot(state['pid']),
        reason: 'Must be a new Android process.',
      );
      final previous = all.firstWhere((b) => b.key.id == state['book']);
      final reopened = BookReaderController(
        book: previous,
        content: content,
        positions: positions,
        preferenceStore: prefs,
        experienceStore: ExperiencePreferencesRepository(db, reader: prefs),
        pageIndexStore: PageIndexRepository(db),
      );
      await reopened.initialize();
      expect(reopened.warning, isNull);
      expect(reopened.focusLocator!.blockId, state['block']);
      expect(reopened.focusLocator!.offsetUtf16, state['offset']);
      expect(reopened.preferences.fontScale, state['scale']);
      expect(reopened.preferences.theme.name, state['theme']);
      await tester.pumpWidget(
        MaterialApp(
          home: BookReaderScreen(
            book: previous,
            content: content,
            controller: reopened,
          ),
        ),
      );
      await settleReader(tester, reopened);
      expect(reopened.pagination!.current, isNotNull);
      expect(reopened.pagination!.total, isNotNull);
      expect(tester.takeException(), isNull);
      if (step == 1) {
        expect(reopened.pagination!.next, isNotNull);
        for (var turn = 0; turn < 20; turn++) {
          await tester.drag(
            find.byType(PageView),
            Offset(turn.isEven ? -300 : 300, 0),
          );
          await settleReader(tester, reopened, saved: true);
          physicalGestures++;
        }
      }
      final before = reopened.visible!;
      final changeClock = Stopwatch()..start();
      final settings = ExperiencePreferences(
        lineHeight: [1.2, 1.5, 1.8][step % 3],
        margins: [12.0, 20.0, 28.0][step % 3],
      );
      await runReaderOperation(
        tester,
        () => reopened.changeExperience(
          settings,
          readerValue: ReaderPreferences(
            fontScale: step.isEven ? 1 : 1.5,
            theme: step.isEven ? ReaderTheme.dark : ReaderTheme.light,
          ),
        ),
      );
      await settleReader(tester, reopened);
      try {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
        ]);
        await tester.pump(const Duration(milliseconds: 250));
        await settleReader(tester, reopened);
        final landscape = [
          tester.view.physicalSize.width,
          tester.view.physicalSize.height,
        ];
        expect(landscape.first, greaterThan(landscape.last));
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        await tester.pump(const Duration(milliseconds: 250));
        await settleReader(tester, reopened);
        expect(
          tester.view.physicalSize.height,
          greaterThan(tester.view.physicalSize.width),
        );
        await runReaderOperation(
          tester,
          () => reopened.changeExperience(
            ExperiencePreferences(
              mode: ReaderMode.scroll,
              lineHeight: settings.lineHeight,
              margins: settings.margins,
            ),
          ),
        );
        await settleReader(tester, reopened);
        expect(reopened.visible!.blockId, before.blockId);
        expect(reopened.visible!.offsetUtf16, before.offsetUtf16);
        await runReaderOperation(
          tester,
          () => reopened.changeExperience(settings),
        );
        await settleReader(tester, reopened);
        expect(reopened.visible!.blockId, before.blockId);
        expect(reopened.visible!.offsetUtf16, before.offsetUtf16);
        expect(reopened.pagination!.total, isNotNull);
        presentationProof = {
          'book': previous.key.id,
          'block': before.blockId,
          'offset': before.offsetUtf16,
          'landscapePixels': landscape,
          'portraitPixels': [
            tester.view.physicalSize.width,
            tester.view.physicalSize.height,
          ],
          'micros': changeClock.elapsedMicroseconds,
          'samePassage': true,
          'modeRoundTrip': true,
        };
      } finally {
        await SystemChrome.setPreferredOrientations([]);
      }
      await tester.pumpWidget(const SizedBox());
      await runReaderOperation(tester, reopened.close);
      expect(jsonEncode(audio), state['audio']);
    }
    final current = all[step % 3];
    final reader = BookReaderController(
      book: current,
      content: content,
      positions: positions,
      preferenceStore: prefs,
      experienceStore: ExperiencePreferencesRepository(db, reader: prefs),
      pageIndexStore: PageIndexRepository(db),
    );
    await reader.initialize();
    await reader.chapter(
      reader.chapters[(step ~/ 3) % reader.chapters.length].id,
    );
    final block = reader.window!.blocks.where((b) => b.text.isNotEmpty).first;
    final offset = step.isEven ? 0 : 1;
    await reader.go(
      BookLocator(
        key: current.key,
        chapterId: block.chapterId,
        blockId: block.id,
        offsetUtf16: offset,
      ),
    );
    await reader.changePreferences(
      ReaderPreferences(
        fontScale: step.isEven ? 1.5 : 1,
        theme: step.isEven ? ReaderTheme.dark : ReaderTheme.light,
      ),
    );
    await reader.flush();
    expect(reader.saveError, isNull);
    final next = {
      'step': step + 1,
      'pid': pid,
      'book': current.key.id,
      'block': block.id,
      'offset': offset,
      'scale': reader.preferences.fontScale,
      'theme': reader.preferences.theme.name,
      'audio': jsonEncode(audio),
    };
    await reader.close();
    await prefs.flush();
    await db.close();
    await marker.writeAsString(jsonEncode(next), flush: true);
    binding.reportData = {
      'resume': {
        'restoresValidated': step,
        'pid': pid,
        'checkpoint': next,
        'database': 'isolated reader.sqlite',
        'foreignAudioRowsUnchanged': true,
        'paged': true,
        'physicalGestures': physicalGestures,
        'presentationProof': presentationProof,
        'productDatabaseOpened': false,
      },
    };
  }, timeout: const Timeout(Duration(minutes: 5)));
}
