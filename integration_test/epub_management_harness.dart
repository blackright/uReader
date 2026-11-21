// Test-only CC0 fixture imports and isolated persistent database; no product DB.
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart'
    show AudioService, AudioServiceConfig;
import 'package:audio_session/audio_session.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/features/library/book_importer.dart';
import 'package:prototype/features/library/book_removal_service.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';
import 'package:prototype/features/model_setup/model_catalog.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';
import 'package:prototype/infrastructure/database/book_content_repository.dart';
import 'package:prototype/infrastructure/database/book_operation_repository.dart';
import 'package:prototype/infrastructure/database/book_audio_cache_repository.dart';
import 'package:prototype/infrastructure/database/book_position_repository.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';
import 'package:prototype/infrastructure/files/book_operation_reconciler.dart';
import 'package:prototype/infrastructure/files/audio_cache.dart';
import 'package:prototype/infrastructure/audio/local_segment_player.dart';
import 'package:prototype/infrastructure/audio/system_audio_handler.dart';
import 'package:prototype/infrastructure/audio/audio_interruption_policy.dart';
import 'package:prototype/infrastructure/speech/platform_speech_engine.dart';
import 'package:prototype/infrastructure/epub/search_key_normalizer.dart';

import '../test/features/library/epub_corpus_import_test.dart'
    show FixtureSource;
import 'epub_reader_resources.dart';

class EpubManagementHarness {
  late Directory root;
  late PrototypeDatabase db;
  late BookRepository books;
  late BookContentRepository content;
  late BookFileStore bookFiles;
  late PrivateFileStore files;
  late BookOperationRepository journal;
  late BookOperationReconciler recovery;
  late BookRemovalService removal;
  PlaybackCoordinator? playback;
  SystemAudioHandler? handler;
  AudioInterruptionPolicy? policy;
  final normalizer = SearchKeyNormalizer();
  final corpus = (jsonDecode(readerCorpusJson) as Map)['books'] as List;
  Future<void> open({Directory? existing, bool audio = false}) async {
    final support = await (await getApplicationSupportDirectory())
        .resolveSymbolicLinks();
    root =
        existing ??
        Directory(
          '$support/us4-management-${DateTime.now().microsecondsSinceEpoch}',
        );
    await root.create(recursive: true);
    db = PrototypeDatabase(NativeDatabase(File('${root.path}/library.sqlite')));
    await db.initialize();
    files = await PrivateFileStore.open(root);
    bookFiles = await BookFileStore.open(root);
    books = BookRepository(db);
    content = BookContentRepository(db, bookFiles);
    journal = BookOperationRepository(db);
    final index = BookAudioCacheRepository(db),
        cache = AudioCache(
          files,
          onRemoved: BookAudioCacheRepository(db).forget,
        );
    recovery = BookOperationReconciler(
      books,
      journal,
      bookFiles,
      purgeAudio: (key) => index.purge(key, cache),
    );
    if (audio) {
      final engine = PlatformSpeechEngine(cache, onPublished: index.record);
      final data = await rootBundle.load('assets/models/manifest.json');
      final catalog = ModelCatalog.fromBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final positions = BookPositionRepository(db, content),
          revisions = <ContentKey, int>{};
      playback = PlaybackCoordinator(
        speech: engine,
        player: LocalSegmentPlayer(cache),
        segmenter: SpeechSegmenter(engine.tokenCount),
        prepareEngine: () => engine.loadBundle(catalog.bundle),
        requestAudioFocus: () => policy!.acquireFocus(),
        discardAudio: cache.remove,
        saveBookAudioPosition: (context, wire, current) async {
          revisions[context.key] ??=
              (await positions.read(
                context.key,
                ReadingMode.audio,
              ))?.revision ??
              0;
          final saved = await positions.saveAudio(
            await context.toBook(wire),
            expectedRevision: revisions[context.key]!,
            isCurrent: current,
          );
          if (saved != null) revisions[context.key] = saved.revision;
        },
      );
      handler = await AudioService.init<SystemAudioHandler>(
        builder: () => SystemAudioHandler(playback!),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.ureader.prototype.playback',
          androidNotificationChannelName: 'Lecture audio',
          androidStopForegroundOnPause: true,
          androidResumeOnClick: false,
        ),
      );
      policy = await AudioInterruptionPolicy.attach(
        playback!,
        await AudioSession.instance,
      );
    }
    removal = BookRemovalService(
      journal: journal,
      files: bookFiles,
      reconciler: recovery,
      releaseTarget: (key) async {
        await playback?.releaseBook(key);
      },
    );
  }

  Future<Book> importAt(int index) async {
    final entry = corpus[index] as Map, id = entry['id'] as String;
    final originals = Directory('${root.path}/originals');
    await originals.create(recursive: true);
    await File('${originals.path}/$id.epub')
        .writeAsBytes(base64Decode(entry['source'] as String));
    final importer = BookImporter(
      source: FixtureSource(bookFiles, entry),
      books: books,
      files: bookFiles,
      normalizeKey: normalizer.normalize,
    );
    try {
      return (await importer.importBook('management-$id', id, 1)).book!;
    } finally {
      await importer.shutdown();
    }
  }

  Future<void> close() async {
    await removal.close();
    await policy?.close();
    await handler?.close();
    await playback?.close();
    await db.close();
  }
}
