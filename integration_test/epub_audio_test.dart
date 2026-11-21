// Actual Pocket TTS/player, injected authorized EPUB archive access.
// Product database/books are not opened; the existing installed voice is reused
// by the native resolver. No second player/coordinator is created.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart'
    show AudioService, AudioServiceConfig;
import 'package:audio_session/audio_session.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/features/library/book_importer.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/content_source_adapter.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';
import 'package:prototype/features/model_setup/model_catalog.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';
import 'package:prototype/infrastructure/database/book_content_repository.dart';
import 'package:prototype/infrastructure/database/book_position_repository.dart';
import 'package:prototype/infrastructure/database/book_audio_cache_repository.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';
import 'package:prototype/infrastructure/files/audio_cache.dart';
import 'package:prototype/infrastructure/audio/local_segment_player.dart';
import 'package:prototype/infrastructure/audio/system_audio_handler.dart';
import 'package:prototype/infrastructure/audio/audio_interruption_policy.dart';
import 'package:prototype/infrastructure/speech/platform_speech_engine.dart';

import '../test/features/library/epub_corpus_import_test.dart'
    show FixtureSource;
import 'epub_reader_resources.dart';
import 'feasibility_bootstrap.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'eight French EPUBs use the same real owner across chapter boundaries',
    (tester) async {
      await waitForNative(tester);
      final support = await (await getApplicationSupportDirectory())
          .resolveSymbolicLinks();
      final root = Directory(
        '$support/us3-epub-audio-validation-${DateTime.now().microsecondsSinceEpoch}',
      );
      await root.create(recursive: true);
      final evidence = Directory('${root.path}/evidence');
      await evidence.create(recursive: true);
      final db = PrototypeDatabase(NativeDatabase.memory());
      final bookFiles = await BookFileStore.open(root);
      final files = await PrivateFileStore.open(root);
      final books = BookRepository(db),
          content = BookContentRepository(db, bookFiles);
      final positions = BookPositionRepository(db, content);
      final cacheIndex = BookAudioCacheRepository(db);
      final cache = AudioCache(files, onRemoved: cacheIndex.forget);
      final manifest = await rootBundle.load('assets/models/manifest.json');
      final catalog = ModelCatalog.fromBytes(
        manifest.buffer.asUint8List(
          manifest.offsetInBytes,
          manifest.lengthInBytes,
        ),
      );
      final captures = <Map<String, Object?>>[];
      final captured = <String>{};
      final chaptersPlayed = <String>{};
      String? activeBook;
      final revisions = <String, int>{};
      Completer<void>? crossed;
      final engine = PlatformSpeechEngine(
        cache,
        onPublished: (key, request, output, bundle) async {
          await cacheIndex.record(key, request, output, bundle);
          final owner = request.bookOwner!;
          final locator = await BookSpeechContext(
            owner,
            content,
          ).toBook(request.start);
          final id = '${owner.id}-${locator.chapterId}';
          if (captured.add(id)) {
            final file = await files.audioCacheFile(key);
            await file.copy('${evidence.path}/$id.wav');
            captures.add({
              'id': id,
              'source': request.text,
              'prepared': request.synthesisText,
              'chapter': locator.chapterId,
              'block': locator.blockId,
              'offset': locator.offsetUtf16,
              'durationMs': output.durationMs,
              'filename': '$id.wav',
            });
          }
        },
      );
      AudioInterruptionPolicy? policy;
      final owner = PlaybackCoordinator(
        speech: engine,
        player: LocalSegmentPlayer(cache),
        segmenter: SpeechSegmenter(engine.tokenCount),
        prepareEngine: () => engine.loadBundle(catalog.bundle),
        discardAudio: cache.remove,
        requestAudioFocus: () => policy!.acquireFocus(),
        saveBookAudioPosition: (context, wire, current) async {
          final locator = await context.toBook(wire);
          final saved = await positions.saveAudio(
            locator,
            expectedRevision: revisions[context.key.id] ?? 0,
            isCurrent: current,
          );
          if (saved != null) {
            revisions[context.key.id] = saved.revision;
            if (context.key.id != activeBook) return;
            chaptersPlayed.add(locator.chapterId);
            if (chaptersPlayed.length >= 2 &&
                crossed != null &&
                !crossed.isCompleted) {
              crossed.complete();
            }
          }
        },
      );
      final handler = await AudioService.init<SystemAudioHandler>(
        builder: () => SystemAudioHandler(owner),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.ureader.prototype.playback',
          androidNotificationChannelName: 'Lecture audio',
          androidStopForegroundOnPause: true,
          androidResumeOnClick: false,
        ),
      );
      policy = await AudioInterruptionPolicy.attach(
        owner,
        await AudioSession.instance,
      );
      final results = <Map<String, Object?>>[];
      final controlResults = <Map<String, Object?>>[];
      final controlStarts = <String>[];
      Completer<void>? controlStarted;
      void observeControl() {
        if (controlStarted == null ||
            owner.state != PlaybackState.playing ||
            owner.playedLocator == null) {
          return;
        }
        controlStarts.add(
          '${owner.bookKey!.id}:${owner.playedLocator!.passageId}',
        );
        if (!controlStarted.isCompleted) controlStarted.complete();
      }

      owner.addListener(observeControl);
      final corpus = jsonDecode(readerCorpusJson) as Map;
      try {
        final frenchBooks = (corpus['books'] as List)
            .where((raw) => (raw as Map)['reference']['language'] == 'fr')
            .toList();
        expect(frenchBooks.length, 8);
        for (final raw in frenchBooks) {
          final entry = raw as Map, id = entry['id'] as String;
          final importer = BookImporter(
            source: FixtureSource(bookFiles, entry),
            books: books,
            files: bookFiles,
            normalizeKey: (s) async => s.toLowerCase(),
          );
          final book = (await importer.importBook('audio-$id', id, 1)).book!;
          await importer.shutdown();
          final chapters = await content.chapters(book.key);
          final chapter = chapters.first;
          BookBlock? lastEligible;
          for (
            var ordinal = chapter.firstBlockOrdinal + chapter.blockCount - 1;
            ordinal >= chapter.firstBlockOrdinal;
            ordinal--
          ) {
            final window = await content.window(
              book.key,
              1,
              after: BookCursor(
                key: book.key,
                generation: 1,
                nextOrdinal: ordinal,
              ),
              maxBlocks: 1,
            );
            final block = window.blocks.single;
            if (block.speechEligible && block.text.trim().isNotEmpty) {
              lastEligible = block;
              break;
            }
          }
          final start = lastEligible!;
          final boundaries = RegExp(r'[.!?]\s+')
              .allMatches(start.text)
              .where((match) => match.end < start.text.trimRight().length)
              .toList();
          final startOffset = boundaries.isEmpty ? 0 : boundaries.last.end;
          chaptersPlayed.clear();
          activeBook = book.key.id;
          crossed = Completer<void>();
          await tester.pumpWidget(
            MaterialApp(home: Scaffold(body: Text('Essai audio EPUB : $id'))),
          );
          final stopwatch = Stopwatch()..start();
          await owner.playBook(
            BookSpeechContext(book.key, content),
            from: BookLocator(
              key: book.key,
              chapterId: start.chapterId,
              blockId: start.id,
              offsetUtf16: startOffset,
            ),
          );
          await crossed.future.timeout(
            const Duration(minutes: 3),
            onTimeout: () {
              fail(
                'No confirmed chapter crossing; state=${owner.state.name}, error=${owner.error?.code.name}',
              );
            },
          );
          expect(owner.positionError, isNull);
          expect(owner.retainedBookSegments, lessThanOrEqualTo(2));
          await owner.stop();
          final saved = await positions.read(book.key, ReadingMode.audio);
          expect(saved, isNotNull);
          results.add({
            'book': id,
            'chaptersStarted': chaptersPlayed.toList(),
            'crossingMs': stopwatch.elapsedMilliseconds,
            'savedBlock': saved!.locator.blockId,
            'sessionOwner': 'single coordinator/player',
            'rssBytes': ProcessInfo.currentRss,
          });
          final progress = {
            'books': results,
            'captures': captures,
            'audioDirectory': 'files/${root.path.split('/').last}/evidence',
            'controls': controlResults,
            'status': 'in_progress',
          };
          binding.reportData = progress;
          await File('${evidence.path}/progress.json')
              .writeAsString(jsonEncode(progress), flush: true);
        }
        final readyBooks = await books.readyPage();
        final firstBook = readyBooks[0], secondBook = readyBooks[1];
        final firstWindow = await content.window(firstBook.key, 1);
        final firstBlock = firstWindow.blocks.firstWhere(
          (b) => b.speechEligible && b.text.trim().isNotEmpty,
        );
        final seekBlock = firstWindow.blocks.lastWhere(
          (b) => b.speechEligible && b.text.trim().isNotEmpty,
        );
        final secondBlock = (await content.window(secondBook.key, 1)).blocks
            .firstWhere((b) => b.speechEligible && b.text.trim().isNotEmpty);
        BookLocator at(BookBlock b) => BookLocator(
          key: b.key,
          chapterId: b.chapterId,
          blockId: b.id,
          offsetUtf16: 0,
        );
        for (var run = 0; run < 5; run++) {
          for (var scenario = 0; scenario < 4; scenario++) {
            controlStarts.clear();
            controlStarted = Completer<void>();
            final started = Stopwatch()..start();
            final initial = owner.playBook(
              BookSpeechContext(firstBook.key, content),
              from: at(firstBlock),
            );
            if (scenario == 0) {
              await owner.pause();
              await initial;
              expect(owner.state, PlaybackState.paused);
              expect(controlStarts, isEmpty);
              await owner.resume();
            } else {
              await initial;
              if (scenario == 1) {
                await owner.stop();
                await Future<void>.delayed(const Duration(milliseconds: 500));
                expect(owner.state, PlaybackState.stopped);
                expect(controlStarts, isEmpty);
              } else if (scenario == 2) {
                await owner.playBook(
                  BookSpeechContext(secondBook.key, content),
                  from: at(secondBlock),
                );
              } else {
                await owner.playBook(
                  BookSpeechContext(firstBook.key, content),
                  from: at(seekBlock),
                );
              }
            }
            if (scenario != 1) {
              await controlStarted.future.timeout(const Duration(seconds: 90));
              final expected = scenario == 2
                  ? '${secondBook.key.id}:${secondBlock.id}'
                  : '${firstBook.key.id}:${scenario == 3 ? seekBlock.id : firstBlock.id}';
              expect(controlStarts.every((s) => s == expected), isTrue);
            }
            expect(owner.retainedBookSegments, lessThanOrEqualTo(2));
            await owner.stop();
            controlStarted = null;
            controlResults.add({
              'run': run,
              'scenario': [
                'pause-resume',
                'stop-preparing',
                'switch-book',
                'seek',
              ][scenario],
              'status': 'passed',
              'elapsedMs': started.elapsedMilliseconds,
              'played': List<String>.from(controlStarts),
            });
          }
        }
        binding.reportData = {
          'books': results,
          'captures': captures,
          'audioDirectory': 'files/${root.path.split('/').last}/evidence',
          'intelligibility': 'not_evaluated; requires human listening',
          'firstAudibleSample': null,
          'sourceAccess': 'injected authorized archive',
          'productDatabaseOpened': false,
          'controls': controlResults,
          'processRestartScenarios': 'not_evaluated in this campaign',
        };
      } finally {
        owner.removeListener(observeControl);
        await policy.close();
        await handler.close();
        await owner.close();
        await positions.flush();
        await db.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
