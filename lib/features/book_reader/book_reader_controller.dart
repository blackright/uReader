import '../../domain/word_alignment.dart';
import 'book_follow_binding.dart';
import 'follow_controller.dart';
import '../../domain/word_selection.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/books.dart';
import '../../domain/bookmarks.dart';
import '../../domain/book_reader.dart';
import '../../domain/content.dart';
import '../../domain/reader_experience.dart';
import '../../domain/pagination.dart';
import '../../domain/paragraph_index.dart';
import 'book_pagination_controller.dart';
import '../../infrastructure/epub/book_link_resolver.dart';
import '../listening/playback_coordinator.dart';
import '../listening/content_source_adapter.dart';
import 'narration_language_controller.dart';

/// Owns only the visual consultation. No reference to an audio engine or player.
class BookReaderController extends ChangeNotifier {
  BookReaderController({
    required this.book,
    required this.content,
    this.positions,
    this.preferenceStore,
    this.experienceStore,
    this.pageIndexStore,
    this.onClosed,
    this.playback,
    this.bookmarkStore,
    this.loadAlignment,
    this.wordAlignmentAvailable = false,
    this.wordAlignmentValidated = false,
  });
  final Book book;
  final bool wordAlignmentAvailable, wordAlignmentValidated;
  final Future<WordAlignment?> Function(String)? loadAlignment;
  late final follow = FollowController(
    wordAlignmentAvailable: wordAlignmentAvailable,
    alignmentValidated: wordAlignmentValidated,
    paragraphFollowing: true,
  );
  BookFollowBinding? _followBinding;
  void userNavigation() => follow.navigation(ReaderNavigationOrigin.user);
  Future<void> setFollowEnabled(bool enabled) async {
    final intent = ++_preferenceIntent;
    final previous = experience;
    final value = ExperiencePreferences(
      mode: previous.mode,
      lineHeight: previous.lineHeight,
      margins: previous.margins,
      followEnabled: enabled,
      presentation: previous.presentation,
      highlightColor: previous.highlightColor,
    );
    try {
      await experienceStore?.save(value);
      if (isClosed || intent != _preferenceIntent) return;
      experience = value;
      if (enabled) {
        follow.resume();
      } else {
        follow.disable();
      }
      _notify();
    } catch (_) {
      warning = 'Le réglage de suivi ne peut pas être enregistré.';
      _notify();
    }
  }

  final BookContentSource content;
  final VisualBookPositionStore? positions;
  final ReaderPreferenceStore? preferenceStore;
  final ExperiencePreferenceStore? experienceStore;
  final PageIndexStore? pageIndexStore;
  BookPaginationController? _pagination;
  bool get supportsPagination =>
      pageIndexStore != null && experienceStore != null && navigation != null;
  BookPaginationController? get pagination {
    if (!supportsPagination) return null;
    return _pagination ??= BookPaginationController(
      key: book.key,
      source: navigation!,
      index: pageIndexStore!,
      onVisible: (locator, block) {
        if (!isClosed &&
            !loading &&
            locator.key == book.key &&
            block.key == book.key) {
          _recordValidated(locator, block);
        }
      },
    );
  }

  final void Function()? onClosed;
  final PlaybackCoordinator? playback;
  final BookmarkStore? bookmarkStore;
  String? narrationMessage;
  BookLocator? savedAudio;
  int _audioReadIntent = 0;
  NarrationLanguage get narrationLanguage =>
      NarrationLanguageController.evaluate(book.languages);
  bool get ownsPlayback => playback?.bookKey == book.key;
  bool get canShowHeard => ownsPlayback && playback?.playedLocator != null;
  BookNavigationSource? get navigation =>
      content is BookNavigationSource ? content as BookNavigationSource : null;
  List<BookChapter> chapters = [];
  final List<BookWindow> _windows = [];
  BookWindow? get window => _windows.isEmpty ? null : _windows.last;
  BookWindow? noteWindow;
  bool _lastBlockEndsParagraph = true;
  bool paragraphEnds(BookBlock block) {
    final blocks = window?.blocks ?? const <BookBlock>[];
    final at = blocks.indexWhere((b) => b.id == block.id);
    if (at < 0 || at + 1 == blocks.length) return _lastBlockEndsParagraph;
    return ParagraphIndex().identity(block) !=
        ParagraphIndex().identity(blocks[at + 1]);
  }

  ReaderPreferences preferences = ReaderPreferences();
  ExperiencePreferences experience = ExperiencePreferences();
  BookLocator? visible, focusLocator, durable;
  BookFailure? error, saveError;
  String? warning;
  bool loading = false, initialized = false;
  int _generation = 0,
      _intent = 0,
      _revision = 0,
      _saveIntent = 0,
      _noteIntent = 0,
      _preferenceIntent = 0;
  bool _closed = false, _closing = false;
  int presentation = 0;
  int? unitsBefore, totalUnits;
  ContentLease? _lease;
  Future<void> _saveTail = Future.value();
  Future<void>? _closeFuture;
  String? fallbackChapter;
  int get retainedWindows => _windows.length + (noteWindow == null ? 0 : 1);
  bool get hasPrevious =>
      window?.blocks.isNotEmpty == true && window!.blocks.first.ordinal > 0;
  bool get isClosed => _closed || _closing;
  void _notify() {
    if (!_closed && !_closing) notifyListeners();
  }

  BookLocator _start(BookBlock b) => BookLocator(
    key: b.key,
    chapterId: b.chapterId,
    blockId: b.id,
    offsetUtf16: 0,
  );
  Future<void> initialize() async {
    if (initialized || isClosed) return;
    playback?.addListener(_audioChanged);
    if (playback != null) {
      _followBinding = BookFollowBinding(
        key: book.key,
        playback: playback!,
        follow: follow,
        loadAlignment: loadAlignment,
      );
    }
    initialized = true;
    loading = true;
    _notify();
    final intent = ++_intent;
    try {
      final lease = await content.acquire(book.key);
      if (isClosed) {
        await lease.release();
        return;
      }
      _lease = lease;
      chapters = await content.chapters(book.key);
      try {
        preferences = await preferenceStore?.read() ?? ReaderPreferences();
        experience = await experienceStore?.read() ?? ExperiencePreferences();
        if (!experience.followEnabled) follow.disable();
      } catch (_) {
        warning = 'Les réglages ne peuvent pas être chargés. Valeurs par défaut utilisées.';
      }
      BookPosition? saved;
      try {
        saved = await positions?.read(book.key, ReadingMode.visual);
      } catch (_) {
        warning = 'Le repère ne peut pas être chargé. Aucune reprise exacte annoncée.';
      }
      if (isClosed || intent != _intent) return;
      try {
        final audio = await positions?.read(book.key, ReadingMode.audio);
        if (audio != null && audio.locator.key == book.key) {
          await content.validateLocator(audio.locator);
          savedAudio = audio.locator;
        } else if (audio != null) {
          narrationMessage = 'Le repère audio est incompatible. Choisissez un passage pour reprendre.';
        }
      } catch (_) {
        narrationMessage =
            'Le repère audio ne peut pas être restauré. Choisissez un passage.';
      }
      if (isClosed || intent != _intent) return;
      _revision = saved?.revision ?? 0;
      if (saved != null) {
        durable = saved.locator;
        try {
          if (saved.locator.key != book.key) {
            throw const BookFailure(BookError.invalidLocator);
          }
          await content.validateLocator(saved.locator);
        } catch (_) {
          warning = 'Le repère enregistré est incompatible. Choisissez un nouveau départ.';
          fallbackChapter =
              chapters.any((c) => c.id == saved!.locator.chapterId)
              ? saved.locator.chapterId
              : '';
          loading = false;
          _notify();
          return;
        }
        await go(saved.locator, savePosition: false);
        return;
      }
      await _load((g) => content.window(book.key, g));
    } on BookFailure catch (e) {
      error = e;
      loading = false;
      _notify();
    } catch (_) {
      error = const BookFailure(BookError.storageUnavailable);
      loading = false;
      _notify();
    }
  }

  Future<void> _load(
    Future<BookWindow> Function(int) operation, {
    BookLocator? focus,
    bool retainPrevious = false,
    bool saveTarget = false,
    bool Function()? stillCurrent,
  }) async {
    if (isClosed) return;
    final intent = ++_intent;
    loading = true;
    error = null;
    ++_noteIntent;
    noteWindow = null;
    _notify();
    await flush();
    if (isClosed || intent != _intent) return;
    final generation = ++_generation;
    try {
      final result = _boundedWindow(await operation(generation));
      if (isClosed || intent != _intent || generation != _generation) return;
      if (stillCurrent != null && !stillCurrent()) {
        loading = false;
        _notify();
        return;
      }
      var endsParagraph = true;
      if (supportsPagination &&
          result.blocks.isNotEmpty &&
          content is ParagraphNavigationSource) {
        final last = result.blocks.last;
        final range = await (content as ParagraphNavigationSource).paragraphAt(
          _start(last),
        );
        endsParagraph = range.lastOrdinal == last.ordinal;
      }
      if (isClosed || intent != _intent || generation != _generation) return;
      if (stillCurrent != null && !stillCurrent()) {
        loading = false;
        _notify();
        return;
      }
      if (result.key != book.key || result.generation != generation) {
        throw const BookFailure(BookError.invalidCursor);
      }
      if (!retainPrevious) _windows.clear();
      _windows.add(result);
      _lastBlockEndsParagraph = endsParagraph;
      while (_windows.length > 2) {
        _windows.removeAt(0);
      }
      visible =
          focus ?? (result.blocks.isEmpty ? null : _start(result.blocks.first));
      focusLocator = visible;
      fallbackChapter = null;
      presentation++;
      loading = false;
      if (saveTarget && visible != null) recordVisible(visible!);
      if (visible != null) await _progress(visible!, generation);
      _notify();
    } on BookFailure catch (e) {
      if (intent == _intent) {
        error = e;
        loading = false;
        _notify();
      }
    } catch (_) {
      if (intent == _intent) {
        error = const BookFailure(BookError.storageUnavailable);
        loading = false;
        _notify();
      }
    }
  }

  BookWindow _boundedWindow(BookWindow value) {
    if (!supportsPagination ||
        experience.mode != ReaderMode.paged ||
        value.blocks.length <= 1) {
      return value;
    }
    return BookWindow(
      key: value.key,
      generation: value.generation,
      blocks: [value.blocks.first],
      next: BookCursor(
        key: value.key,
        generation: value.generation,
        nextOrdinal: value.blocks.first.ordinal + 1,
      ),
    );
  }

  Future<void> go(
    BookLocator locator, {
    bool savePosition = true,
    ReaderNavigationOrigin origin = ReaderNavigationOrigin.user,
    bool Function()? stillCurrent,
  }) async {
    follow.navigation(origin);
    final nav = navigation;
    if (nav == null) {
      await _load((g) => content.window(book.key, g));
      return;
    }
    await _load(
      (g) => nav.windowAt(locator, g),
      focus: locator,
      saveTarget: savePosition,
      stillCurrent: stillCurrent,
    );
  }

  Future<void> chapter(String id) async {
    userNavigation();
    final selected = chapters.where((c) => c.id == id).firstOrNull;
    if (selected == null) throw const BookFailure(BookError.invalidLocator);
    await _load(
      (g) => content.window(
        book.key,
        g,
        after: BookCursor(
          key: book.key,
          generation: g,
          nextOrdinal: selected.firstBlockOrdinal,
        ),
      ),
      saveTarget: true,
    );
  }

  Future<void> fallback() async {
    final chapterId = fallbackChapter;
    if (chapterId != null && chapterId.isNotEmpty) {
      await chapter(chapterId);
    } else {
      await _load((g) => content.window(book.key, g), saveTarget: true);
    }
  }

  Future<void> next() async {
    final next = window?.next;
    if (next == null || loading) return;
    await _load(
      (g) => content.window(
        book.key,
        g,
        after: BookCursor(
          key: book.key,
          generation: g,
          nextOrdinal: next.nextOrdinal,
        ),
      ),
      retainPrevious: true,
      saveTarget: true,
    );
  }

  Future<void> previous() async {
    if (!hasPrevious || loading || navigation == null) return;
    final start = window!.blocks.first.ordinal;
    await _load(
      (g) => navigation!.windowBefore(book.key, g, start),
      saveTarget: true,
    );
  }

  Future<void> _progress(BookLocator locator, int generation) async {
    try {
      final value = await navigation?.progress(locator);
      if (generation != _generation || isClosed) return;
      unitsBefore = value?.$1;
      totalUnits = value?.$2;
    } catch (_) {
      /* Progress is informative, never a false duration. */
    }
  }

  void recordVisible(BookLocator locator) {
    if (isClosed || loading || locator.key != book.key) return;
    final b = window?.blocks.where((b) => b.id == locator.blockId).firstOrNull;
    if (b == null) return;
    _recordValidated(locator, b);
  }

  int _pageVisibleIntent = 0;
  Future<void> recordPagedVisible(BookLocator locator) async {
    final source = navigation, intent = _intent, serial = ++_pageVisibleIntent;
    if (source == null || isClosed || loading || locator.key != book.key) {
      return;
    }
    try {
      final block = await source.block(book.key, locator.blockId);
      if (isClosed ||
          loading ||
          intent != _intent ||
          serial != _pageVisibleIntent) {
        return;
      }
      _recordValidated(locator, block);
    } catch (_) {
      if (!isClosed && intent == _intent && serial == _pageVisibleIntent) {
        saveError = const BookFailure(BookError.storageUnavailable);
        _notify();
      }
    }
  }

  void _recordValidated(BookLocator locator, BookBlock b) {
    try {
      locator.validate(b);
    } on BookFailure {
      return;
    }
    if (visible?.blockId == locator.blockId &&
        visible?.offsetUtf16 == locator.offsetUtf16 &&
        durable?.key == locator.key &&
        durable?.blockId == locator.blockId &&
        durable?.offsetUtf16 == locator.offsetUtf16) {
      return;
    }
    visible = locator;
    final serial = ++_saveIntent, generation = _generation;
    _saveTail = _saveTail.then((_) async {
      if (_closed || generation != _generation || serial != _saveIntent) return;
      try {
        final saved = await positions?.saveVisual(
          locator,
          expectedRevision: _revision,
          isCurrent: () =>
              !_closed && generation == _generation && serial == _saveIntent,
        );
        if (saved != null) {
          _revision = saved.revision;
          durable = saved.locator;
          saveError = null;
        }
        await _progress(locator, generation);
        _notify();
      } on BookFailure catch (e) {
        saveError = e;
        _notify();
      } catch (_) {
        saveError = const BookFailure(BookError.storageUnavailable);
        _notify();
      }
    });
  }

  Future<void> retrySave() async {
    final locator = visible;
    if (locator == null || positions == null) return;
    try {
      final stored = await positions!.read(book.key, ReadingMode.visual);
      _revision = stored?.revision ?? 0;
      durable = null;
      if (supportsPagination) {
        await recordPagedVisible(locator);
      } else {
        recordVisible(locator);
      }
      await flush();
    } catch (_) {
      saveError = const BookFailure(BookError.storageUnavailable);
      _notify();
    }
  }

  Future<void> flush() async {
    await _saveTail;
    await positions?.flush();
    await experienceStore?.flush();
  }

  Future<void> changePreferences(ReaderPreferences value) async {
    if (experienceStore != null) {
      await changeExperience(experience, readerValue: value);
      return;
    }
    final intent = ++_preferenceIntent;
    try {
      await preferenceStore?.save(value);
      if (isClosed || intent != _preferenceIntent) return;
      preferences = value;
      final locator = visible;
      if (locator != null && navigation != null) {
        await go(locator, savePosition: false);
      } else {
        focusLocator = visible;
        presentation++;
        _notify();
      }
    } catch (_) {
      warning = 'Les réglages ne sont pas enregistrés. Réessayez.';
      _notify();
    }
  }

  Future<void> changeExperience(
    ExperiencePreferences value, {
    ReaderPreferences? readerValue,
  }) async {
    final store = experienceStore;
    if (store == null || isClosed) return;
    final intent = ++_preferenceIntent;
    try {
      await store.save(value, reader: readerValue);
      if (isClosed || intent != _preferenceIntent) return;
      if (value.mode == ReaderMode.scroll) await _pagination?.suspend();
      if (isClosed || intent != _preferenceIntent) return;
      final wasFollowing = experience.followEnabled;
      experience = value;
      if (!value.followEnabled) {
        follow.disable();
      } else if (!wasFollowing) {
        follow.resume();
      }
      preferences = readerValue ?? preferences;
      final locator = visible;
      if (locator != null && navigation != null) {
        await go(locator, savePosition: false);
      } else {
        focusLocator = visible;
        presentation++;
        _notify();
      }
    } catch (_) {
      warning = 'Les réglages ne sont pas enregistrés. Réessayez.';
      _notify();
    }
  }

  Future<ResolvedBookLink> resolve(BookBlock block, String target) async {
    final source = chapters.where((c) => c.id == block.chapterId).firstOrNull;
    if (source == null) throw const BookFailure(BookError.unsafeLink);
    return BookLinkResolver.resolve(source.resource, target);
  }

  Future<BookLocator> internalTarget(ResolvedBookLink link) async {
    final resource = link.resource;
    if (resource == null) throw const BookFailure(BookError.unsafeLink);
    if (link.fragment.isNotEmpty) {
      return content.resolveAnchor(book.key, resource, link.fragment);
    }
    final target = chapters.where((c) => c.resource == resource).firstOrNull;
    if (target == null || navigation == null) {
      throw const BookFailure(BookError.invalidLocator);
    }
    final w = await content.window(
      book.key,
      _generation,
      after: BookCursor(
        key: book.key,
        generation: _generation,
        nextOrdinal: target.firstBlockOrdinal,
      ),
      maxBlocks: 1,
    );
    if (w.blocks.isEmpty) throw const BookFailure(BookError.invalidLocator);
    return _start(w.blocks.first);
  }

  Future<BookWindow> openNote(BookLocator locator) async {
    userNavigation();
    final intent = ++_noteIntent;
    final nav = navigation;
    if (nav == null) throw const BookFailure(BookError.unsupportedContent);
    if (_windows.length > 1) _windows.removeAt(0);
    final generation = _generation;
    final result = _boundedWindow(await nav.windowAt(locator, generation));
    if (isClosed || generation != _generation || intent != _noteIntent) {
      throw const BookFailure(BookError.cancelled);
    }
    noteWindow = result;
    return result;
  }

  Future<BookWindow?> continueNote() async {
    final intent = ++_noteIntent;
    final next = noteWindow?.next;
    if (next == null) return null;
    final generation = _generation;
    final result = _boundedWindow(
      await content.window(book.key, generation, after: next),
    );
    if (isClosed || generation != _generation || intent != _noteIntent) {
      throw const BookFailure(BookError.cancelled);
    }
    noteWindow = result;
    return result;
  }

  void closeNote() {
    ++_noteIntent;
    noteWindow = null;
  }

  Future<void> close() => _closeFuture ??= _close();
  void _audioChanged() {
    _notify();
    if (ownsPlayback) unawaited(_refreshAudioResume());
  }

  Future<void> _refreshAudioResume() async {
    final intent = ++_audioReadIntent;
    try {
      final saved = await positions?.read(book.key, ReadingMode.audio);
      if (isClosed || !ownsPlayback || intent != _audioReadIntent) return;
      if (saved != null && saved.locator.key == book.key) {
        savedAudio = saved.locator;
        _notify();
      }
    } catch (_) {
      // The coordinator surfaces durable-write errors; do not invent a repère.
    }
  }

  Future<void> listenHere({
    WordSelection? word,
    bool frenchConfirmed = false,
    bool resumeSaved = false,
    bool prepareChapter = false,
    BookLocator? from,
  }) async {
    final owner = playback, source = navigation;
    final locator = word?.start ?? from ?? (resumeSaved ? savedAudio : visible);
    if (isClosed || owner == null || source == null || locator == null) return;
    if (narrationLanguage == NarrationLanguage.unsupported) {
      narrationMessage = 'La narration est disponible en français uniquement. Ce livre reste lisible.';
      _notify();
      return;
    }
    if (narrationLanguage == NarrationLanguage.confirmationRequired &&
        !frenchConfirmed) {
      narrationMessage = 'Confirmez la lecture en français pour ce livre.';
      _notify();
      return;
    }
    narrationMessage = null;
    if (experience.followEnabled) follow.resume();
    final context = BookSpeechContext(book.key, source);
    try {
      if (word != null) {
        await owner.playFromWord(context, word, prepareChapter: prepareChapter);
      } else if (resumeSaved || source is! ParagraphNavigationSource) {
        await owner.playBook(
          context,
          from: locator,
          prepareChapter: prepareChapter,
        );
      } else {
        await owner.playFromParagraph(
          context,
          locator,
          prepareChapter: prepareChapter,
        );
      }
    } on BookFailure catch (failure) {
      narrationMessage = failure.message;
    }
    _notify();
  }

  Future<void> showHeard() async {
    final locator = playback?.playedLocator;
    final source = navigation;
    if (!canShowHeard || locator == null || source == null) return;
    final context = BookSpeechContext(book.key, source);
    await go(await context.toBook(locator));
  }

  Future<void> _close() async {
    _closing = true;
    playback?.removeListener(_audioChanged);
    await _followBinding?.close();
    follow.dispose();
    ++_intent;
    await _pagination?.close();
    await flush();
    _closed = true;
    ++_generation;
    noteWindow = null;
    _windows.clear();
    await _lease?.release();
    _lease = null;
    onClosed?.call();
    super.dispose();
  }
}
