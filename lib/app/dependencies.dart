import '../infrastructure/audio/alignment_cache.dart';
import '../infrastructure/speech/alignment_provider.dart';
import '../domain/book_reader.dart' show ReaderTheme;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../domain/ports.dart';
import '../domain/content.dart';
import '../features/feasibility/report_repository.dart';
import '../features/model_setup/model_catalog.dart';
import '../features/model_setup/bundle_reattestation.dart';
import '../features/model_setup/model_operation_gate.dart';
import '../features/model_setup/model_installer.dart';
import '../features/model_setup/model_removal_service.dart';
import '../infrastructure/files/android_local_bundle_source.dart';
import '../domain/app_error.dart';
import '../features/listening/playback_coordinator.dart';
import '../features/audio_player/player_presenter.dart';
import '../features/listening/speech_segmenter.dart';
import '../infrastructure/audio/local_segment_player.dart';
import '../infrastructure/audio/system_audio_handler.dart';
import '../infrastructure/audio/audio_interruption_policy.dart';
import '../infrastructure/database/position_repository.dart';
import '../features/demo_reader/reader_controller.dart';
import '../infrastructure/files/audio_cache.dart';
import '../infrastructure/speech/platform_speech_engine.dart';
import '../features/demo_reader/corpus_repository.dart';
import '../infrastructure/database/prototype_database.dart';
import '../infrastructure/diagnostics/safe_diagnostics.dart';
import '../infrastructure/files/operation_reconciler.dart';
import '../infrastructure/files/private_file_store.dart';
import '../infrastructure/speech/speech_messages.dart';

import '../domain/books.dart';
import '../features/book_reader/book_reader_controller.dart';
import '../infrastructure/database/book_position_repository.dart';
import '../infrastructure/database/book_audio_cache_repository.dart';
import '../infrastructure/database/book_preferences_repository.dart';
import '../infrastructure/database/experience_preferences_repository.dart';
import '../infrastructure/database/page_index_repository.dart';
import '../features/library/book_importer.dart';
import '../features/library/book_removal_service.dart';
import '../infrastructure/epub/android_document_source.dart';
import '../infrastructure/epub/epub_import_source.dart';
import '../infrastructure/epub/search_key_normalizer.dart';
import '../infrastructure/files/book_file_store.dart';
import '../infrastructure/files/book_operation_reconciler.dart';
import '../infrastructure/database/book_repository.dart';
import '../infrastructure/database/bookmark_repository.dart';
import '../infrastructure/database/book_content_repository.dart';
import '../infrastructure/database/book_operation_repository.dart';

class AppDependencies {
  AppDependencies._({
    required this.database,
    required this.files,
    required this.speech,
    required this.clock,
    required this.diagnostics,
    required this.corpus,
    required this.models,
    required this.modelRemoval,
    this.playback,
    this.systemAudio,
    this.interruptions,
    required this.positions,
    required this.reader,
    required this.bookFiles,
    required this.books,
    required this.bookContent,
    required this.bookPositions,
    required this.bookPreferences,
    required this.initialReaderTheme,
    required this.bookImporter,
    required this.normalizeBookKey,
    required this.bookRecoveryIssues,
  });
  final PrototypeDatabase database;
  final ModelInstaller? models;
  final ModelRemovalService modelRemoval;
  final PrivateFileStore files;
  ReportRepository get reports => ReportRepository(files.root);
  final SpeechEngine speech;
  final AppClock clock;
  final SafeDiagnostics diagnostics;
  final CorpusRepository corpus;
  final PlaybackCoordinator? playback;
  final SystemAudioHandler? systemAudio;
  PlayerPresenter? _playerPresenter;
  PlayerPresenter? get playerPresenter {
    final owner = playback;
    if (owner == null) return null;
    return _playerPresenter ??= PlayerPresenter(
      owner: owner,
      source: bookContent,
      preferences: experiencePreferences,
      lookup: (key) async {
        final value = await books.playerBook(key);
        return value == null
            ? null
            : PlayerBook(value.book, coverResource: value.cover);
      },
    )..initialize();
  }

  final AudioInterruptionPolicy? interruptions;
  final PositionRepository positions;
  final ReaderController reader;
  final BookFileStore bookFiles;
  final BookRepository books;
  final BookContentRepository bookContent;
  final BookPositionRepository bookPositions;
  final BookPreferencesRepository bookPreferences;
  final ReaderTheme initialReaderTheme;
  late final experiencePreferences = ExperiencePreferencesRepository(
    database,
    reader: bookPreferences,
  );
  late final pageIndex = PageIndexRepository(database);
  late final bookmarks = BookmarkRepository(database, bookContent);
  BookRemovalService? _bookRemoval;
  BookRemovalService get bookRemoval => _bookRemoval ??= BookRemovalService(
    journal: BookOperationRepository(database),
    files: bookFiles,
    reconciler: BookOperationReconciler(
      books,
      BookOperationRepository(database),
      bookFiles,
      purgeAudio: (key) => BookAudioCacheRepository(database).purge(
        key,
        AudioCache(files, onRemoved: BookAudioCacheRepository(database).forget),
      ),
    ),
    releaseTarget: (key) async {
      await playback?.releaseBook(key);
      await bookmarks.flush();
      await Future.wait(
        _bookReaders
            .where((r) => r.book.key == key)
            .toList()
            .map((r) => r.close()),
      );
    },
  );
  final _bookReaders = <BookReaderController>{};
  BookReaderController createBookReader(Book book) {
    late BookReaderController controller;
    controller = BookReaderController(
      book: book,
      content: bookContent,
      positions: bookPositions,
      preferenceStore: bookPreferences,
      experienceStore: experiencePreferences,
      pageIndexStore: pageIndex,
      playback: playback,
      bookmarkStore: bookmarks,
      loadAlignment: AlignmentCache(files).read,
      wordAlignmentAvailable: models?.catalog.alignmentAvailable ?? false,
      wordAlignmentValidated: models?.catalog.alignmentQualified ?? false,
      onClosed: () => _bookReaders.remove(controller),
    );
    _bookReaders.add(controller);
    return controller;
  }

  final BookImporter bookImporter;
  final Future<String> Function(String) normalizeBookKey;
  final List<BookFailure> bookRecoveryIssues;
  Future<void>? _disposeFuture;

  static Future<AppDependencies> open({
    Directory? directory,
    QueryExecutor? executor,
    AppClock? clock,
    CorpusRepository? corpus,
    Future<ByteData> Function()? loadSpeechManifest,
    EpubImportSource? documents,
    Future<String> Function(String)? bookKeyNormalizer,
  }) async {
    Directory root;
    if (directory != null) {
      root = directory;
    } else {
      // Résoudre l'emplacement fourni par le système avant de contrôler notre
      // sous-répertoire : certains systèmes utilisent des alias de stockage.
      final support = await getApplicationSupportDirectory();
      await support.create(recursive: true);
      root = Directory(
        p.join(await support.resolveSymbolicLinks(), 'ureader-prototype'),
      );
    }
    final files = await PrivateFileStore.open(root);
    final db = PrototypeDatabase(
      executor ?? NativeDatabase.createInBackground(await files.databaseFile()),
    );
    final actualClock = clock ?? SystemClock();
    final diagnostics = SafeDiagnostics(clock: actualClock);
    try {
      await db.initialize();
      final bookFiles = await BookFileStore.open(root);
      final books = BookRepository(db);
      final bookContent = BookContentRepository(db, bookFiles);
      final bookPositions = BookPositionRepository(db, bookContent);
      final bookPreferences = BookPreferencesRepository(db);
      final searchNormalizer = SearchKeyNormalizer();
      Future<String> normalizeBookKey(String text) async => text.isEmpty
          ? ''
          : await (bookKeyNormalizer ?? searchNormalizer.normalize)(text);
      final bookImporter = BookImporter(
        source: documents ?? AndroidDocumentSource(),
        books: books,
        files: bookFiles,
        normalizeKey: normalizeBookKey,
      );
      List<BookFailure> bookIssues;
      try {
        bookIssues = await BookOperationReconciler(
          books,
          BookOperationRepository(db),
          bookFiles,
          purgeAudio: (key) => BookAudioCacheRepository(db).purge(
            key,
            AudioCache(files, onRemoved: BookAudioCacheRepository(db).forget),
          ),
        ).recover();
      } catch (_) {
        bookIssues = [const BookFailure(BookError.storageUnavailable)];
        diagnostics.record(
          DiagnosticEvent.recoveryFailed,
          error: ErrorCode.storageUnavailable,
        );
      }

      ModelCatalog? parsedCatalog;
      try {
        const requestedProfile = String.fromEnvironment(
          'UREADER_SPEECH_PROFILE',
          defaultValue: 'kokoro',
        );
        final manifestAsset = switch (requestedProfile) {
          'pocket' => 'assets/models/manifest.json',
          'kokoro' => 'assets/models/kokoro-manifest.json',
          _ => throw const AppError(ErrorCode.modelIntegrityFailed),
        };
        final manifestData =
            await (loadSpeechManifest?.call() ??
                rootBundle.load(manifestAsset));
        parsedCatalog = ModelCatalog.fromBytes(
          manifestData.buffer.asUint8List(
            manifestData.offsetInBytes,
            manifestData.lengthInBytes,
          ),
        );
      } catch (_) {
        diagnostics.record(
          DiagnosticEvent.recoveryFailed,
          error: ErrorCode.modelIntegrityFailed,
        );
      }
      final catalog = parsedCatalog;
      final positions = PositionRepository(
        db,
        latestVisual: db.readLatestVisualPosition,
      );
      await OperationReconciler(
        journal: db,
        files: files,
        resolveTrustedBundle: catalog?.resolve ?? (_, _, _) async => null,
        diagnostics: diagnostics,
      ).reconcile();
      final modelGate = ModelOperationGate();
      if (catalog != null) {
        await BundleReattestation(
          database: db,
          files: files,
          gate: modelGate,
        ).run(catalog);
      }
      SpeechEngine speech = UnavailableSpeechEngine();
      PlaybackCoordinator? playback;
      SystemAudioHandler? systemAudio;
      AudioInterruptionPolicy? interruptions;
      if (Platform.isAndroid) {
        final bookCache = BookAudioCacheRepository(db);
        final cache = AudioCache(files, onRemoved: bookCache.forget);
        final engine = PlatformSpeechEngine(
          cache,
          onPublished: bookCache.record,
          alignmentProvider: AttentionAlignmentProvider(
            enabled: catalog?.alignmentAvailable ?? false,
          ),
        );
        ContentKey? audioBookKey;
        var audioBookRevision = 0;
        speech = engine;
        try {
          final session = await AudioSession.instance;
          playback = PlaybackCoordinator(
            voiceId: catalog?.voiceId ?? 'estelle',
            bundleId: catalog?.bundle.id ?? 'fr-official-aligned',
            speech: engine,
            player: LocalSegmentPlayer(cache),
            segmenter: SpeechSegmenter(engine.tokenCount),
            discardAudio: cache.retainForReplay,
            releaseAudioBatch: (_) => cache.trimReplay(),
            holdPreparedAudio: (key) async {
              final lease = await files.acquire('cache/audio/$key.wav');
              return lease.release;
            },
            unloadEngine: engine.unloadBundle,
            requestAudioFocus: () => interruptions!.acquireFocus(),
            saveAudioPosition: (text, locator, current) async =>
                (await positions.save(
                  text,
                  locator,
                  ReadingMode.audio,
                  isCurrent: current,
                ))?.locator,
            saveBookAudioPosition: (context, wire, current) async {
              if (!current()) return;
              if (audioBookKey != context.key) {
                audioBookRevision =
                    (await bookPositions.read(
                      context.key,
                      ReadingMode.audio,
                    ))?.revision ??
                    0;
                audioBookKey = context.key;
              }
              final locator = await context.toBook(wire);
              final saved = await bookPositions.saveAudio(
                locator,
                expectedRevision: audioBookRevision,
                isCurrent: current,
              );
              if (saved != null) audioBookRevision = saved.revision;
            },
            prepareEngine: () async {
              if (catalog == null || !catalog.demonstrated) {
                throw const AppError(ErrorCode.engineUnavailable);
              }
              if (!await db.isBundleReady(catalog.bundle)) {
                throw const AppError(ErrorCode.modelMissing);
              }
              await engine.loadBundle(catalog.bundle);
            },
          );
          systemAudio = await AudioService.init<SystemAudioHandler>(
            builder: () => SystemAudioHandler(playback!),
            config: const AudioServiceConfig(
              androidNotificationChannelId: 'com.ureader.prototype.playback',
              androidNotificationChannelName: 'Lecture audio',
              // Release foreground status/wake lock on pause or stop. Resume is
              // an explicit UI/media action, never a restored-session autoplay.
              androidStopForegroundOnPause: true,
              androidResumeOnClick: false,
            ),
          );
          interruptions = await AudioInterruptionPolicy.attach(
            playback,
            session,
          );
        } catch (_) {
          await interruptions?.close();
          await systemAudio?.close();
          await playback?.close();
          playback = null;
          systemAudio = null;
          interruptions = null;
          speech = UnavailableSpeechEngine();
          diagnostics.record(
            DiagnosticEvent.recoveryFailed,
            error: ErrorCode.engineUnavailable,
          );
        }
      }
      final localSource = Platform.isAndroid
          ? AndroidLocalBundleSource()
          : UnavailableLocalBundleSource();
      final models = catalog == null
          ? null
          : ModelInstaller(
              gate: modelGate,
              catalog: catalog,
              files: files,
              database: db,
              source: localSource,
              hasSpace: localSource is AndroidLocalBundleSource
                  ? localSource.hasSpace
                  : null,
              beforePublication: playback?.suspendVoice,
              onSettled: playback?.resumeVoice,
            );
      final removal = ModelRemovalService(
        gate: modelGate,
        files: files,
        database: db,
        releaseVoice: playback?.suspendVoice ?? () async {},
        resumeVoice: playback?.resumeVoice ?? () {},
      );
      final actualCorpus = corpus ?? CorpusRepository();
      final reader = ReaderController(
        corpus: actualCorpus,
        positions: positions,
        playback: playback,
      );
      var initialReaderTheme = ReaderTheme.light;
      try {
        initialReaderTheme = (await bookPreferences.read()).theme;
      } on BookFailure {
        // A presentation preference failure leaves the library usable.
      }
      return AppDependencies._(
        database: db,
        files: files,
        speech: speech,
        playback: playback,
        systemAudio: systemAudio,
        interruptions: interruptions,
        corpus: actualCorpus,
        positions: positions,
        reader: reader,
        clock: actualClock,
        diagnostics: diagnostics,
        models: models,
        modelRemoval: removal,
        bookFiles: bookFiles,
        books: books,
        bookContent: bookContent,
        bookPositions: bookPositions,
        bookPreferences: bookPreferences,
        initialReaderTheme: initialReaderTheme,
        bookImporter: bookImporter,
        normalizeBookKey: normalizeBookKey,
        bookRecoveryIssues: List.unmodifiable(bookIssues),
      );
    } catch (_) {
      await db.close();
      rethrow;
    }
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    await bookImporter.shutdown();
    await _bookRemoval?.close();
    await _playerPresenter?.flush();
    _playerPresenter?.dispose();
    await Future.wait(_bookReaders.toList().map((r) => r.close()));
    await bookmarks.flush();
    await bookPositions.flush();
    await bookPreferences.flush();
    reader.dispose();
    await modelRemoval.close();
    await models?.close();
    await interruptions?.close();
    await systemAudio?.close();
    if (playback != null) {
      await playback!.close();
    } else {
      await speech.dispose();
    }
    await positions.flush();
    await database.close();
  }
}
