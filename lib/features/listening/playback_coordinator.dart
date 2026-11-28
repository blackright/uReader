import '../../domain/word_alignment.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/app_error.dart';
import '../../domain/content.dart';
import '../../domain/ports.dart';
import '../../domain/books.dart';
import '../../domain/word_selection.dart';
import '../book_reader/word_selection_source.dart';
import '../../domain/book_reader.dart';
import 'content_source_adapter.dart';
import 'book_segment_cursor.dart';
import 'speech_segmenter.dart';

enum PlaybackState { stopped, preparing, playing, paused, completed, error }

class PlaybackCoordinator extends ChangeNotifier {
  PlaybackCoordinator({
    required this.speech,
    required this.player,
    required this.segmenter,
    required this.prepareEngine,
    required this.discardAudio,
    this.voiceId = 'estelle',
    this.bundleId = 'fr-official-aligned',
    this.unloadEngine,
    this.requestAudioFocus,
    this.saveAudioPosition,
    this.saveBookAudioPosition,
    this.holdPreparedAudio,
    this.releaseAudioBatch,
    this.initialBuffer = const Duration(seconds: 20),
    // Bank fast passages before a slower stretch; a one-minute ceiling ran dry
    // despite generation being faster than playback over the complete book test.
    this.targetBuffer = const Duration(seconds: 120),
    this.maxBufferedSegments = 12,
    this.maxPreparedSegments = 64,
    this.adaptiveBuffer = true,
  }) {
    requireIdentifier(voiceId);
    requireIdentifier(bundleId);
    if (initialBuffer < Duration.zero ||
        targetBuffer < initialBuffer ||
        maxBufferedSegments < 2 ||
        maxBufferedSegments > 12 ||
        maxPreparedSegments < maxBufferedSegments ||
        maxPreparedSegments > 64) {
      throw ArgumentError('Invalid audio buffer budget');
    }
    _speechSub = speech.events.listen(
      (event) => _enqueue(() => _speechEvent(event)),
    );
    _playerSub = player.events.listen(
      (event) => _enqueue(() => _playerEvent(event)),
    );
  }
  final Future<void Function()> Function(String)? holdPreparedAudio;
  final Future<void> Function(Iterable<String>)? releaseAudioBatch;
  final _preparedLeases = <int, void Function()>{};
  bool _prepareChapter = false;
  bool get preparingChapter => _prepareChapter && !_producerDone;
  String get completionStatus =>
      _prepareChapter ? 'Fin du chapitre préparé' : 'Fin du livre';
  final Duration initialBuffer, targetBuffer;
  final int maxBufferedSegments, maxPreparedSegments;
  final bool adaptiveBuffer;
  final _requestClocks = <String, Stopwatch>{};
  double? _warmRtf;
  int get bufferTargetMs =>
      (targetBuffer.inMilliseconds *
              (adaptiveBuffer && (_warmRtf ?? 0) > 0.9 ? 1.5 : 1))
          .round();
  bool get _buffered => player is BufferedAudioPlayer;
  BufferedAudioPlayer get _playlist => player as BufferedAudioPlayer;
  final _queued = <int>{};
  final _pendingRetirement = <SessionToken>[];
  bool _producerDone = false, _producerBusy = false;
  int _nextProduce = 0;
  Future<void>? _producerWork;
  int get preparedAudioMs => _outputs.entries
      .where((e) => e.key >= _index)
      .fold(0, (sum, e) => sum + e.value.durationMs);
  int get preparedSegments => _outputs.length;
  String get preparationStatus => preparingChapter
      ? 'Préparation du chapitre : $preparedSegments passages, ${(preparedAudioMs / 60000).toStringAsFixed(1)} min prêtes'
      : _buffered
      ? 'Préparation de l’écoute : ${(preparedAudioMs / 1000).toStringAsFixed(1)} s prêtes'
      : 'Préparation de la voix';
  final SpeechEngine speech;
  final String voiceId, bundleId;
  final AudioPlayer player;
  final SpeechSegmenter segmenter;
  final Future<void> Function() prepareEngine;
  final Future<void> Function(String) discardAudio;
  final Future<void> Function()? unloadEngine;
  final Future<bool> Function()? requestAudioFocus;
  final Future<Locator?> Function(DemoText, Locator, bool Function())?
  saveAudioPosition;
  final Future<void> Function(BookSpeechContext, Locator, bool Function())?
  saveBookAudioPosition;
  final _retiredBooks = <ContentKey>{};
  AppError? positionError;
  Locator? durableLocator;

  Future<void> _savePlayed(
    DemoText? text,
    Locator? locator, {
    bool Function()? isCurrent,
    BookSpeechContext? book,
  }) async {
    if (book != null && _retiredBooks.contains(book.key)) {
      positionError = null;
      return;
    }
    if (book != null && locator != null && saveBookAudioPosition != null) {
      try {
        await saveBookAudioPosition!(book, locator, isCurrent ?? () => true);
        positionError = null;
      } catch (_) {
        positionError = _retiredBooks.contains(book.key)
            ? null
            : const AppError(ErrorCode.storageUnavailable);
      }
      if (!_closed) notifyListeners();
      return;
    }
    if (text == null ||
        locator == null ||
        locator.textId != text.id ||
        saveAudioPosition == null) {
      return;
    }
    try {
      final saved = await saveAudioPosition!(
        text,
        locator,
        isCurrent ?? () => true,
      );
      if (saved != null) {
        durableLocator = saved;
        positionError = null;
      }
    } catch (_) {
      positionError = const AppError(ErrorCode.storageUnavailable);
    }
    if (!_closed) notifyListeners();
  }

  bool _voiceSuspended = false;
  Future<void> suspendVoice() async {
    _voiceSuspended = true;
    await stop();
    await unloadEngine?.call();
    _loaded = false;
    _segments = [];
  }

  void resumeVoice() {
    _voiceSuspended = false;
  }

  late final StreamSubscription<SpeechEvent> _speechSub;
  late final StreamSubscription<PlayerEvent> _playerSub;
  PlaybackState state = PlaybackState.stopped;
  AppError? error;
  Locator? playedLocator;
  DemoText? _text;
  BookSpeechContext? _book;
  SpeechSegmentCursor? _segmentCursor;
  final _bookSegments = <int, SpeechSegment>{};
  ContentKey? get bookKey => _book?.key;
  BookSpeechContext? get bookContext => _book;
  int get sessionGeneration => _generation;
  BookLocator? targetLocator;
  String? bookNotice;
  String? mediaTitle, mediaAuthor, mediaChapter;
  void publishBookMetadata(
    ContentKey key, {
    required String title,
    String? author,
    String? chapter,
  }) {
    if (_closed || key != bookKey) return;
    if (mediaTitle == title &&
        mediaAuthor == author &&
        mediaChapter == chapter) {
      return;
    }
    mediaTitle = title;
    mediaAuthor = author;
    mediaChapter = chapter;
    notifyListeners();
  }

  SpeechSegment? get activeSegment => _book != null
      ? _bookSegments[_index]
      : (_index < _segments.length ? _segments[_index] : null);
  SpeechOutput? get activeOutput => _outputs[_index];
  SessionToken get activePlayerToken => _playerToken;

  /// Called only with a hash-validated clock/alignment join; persisted on pause/stop.
  void recordAlignedPosition(PlayerClockSample sample, SourceSpan span) {
    final segment = activeSegment;
    if (_closed ||
        sample.state != PlayerClockState.playing ||
        !_currentPlayer(sample.token) ||
        state != PlaybackState.playing ||
        sample.segmentId != activeOutput?.audioHandle ||
        segment == null ||
        span.start < segment.start.offsetUtf16 ||
        span.end > segment.end.offsetUtf16) {
      return;
    }
    playedLocator = Locator(
      textId: segment.start.textId,
      corpusVersion: segment.start.corpusVersion,
      passageId: segment.start.passageId,
      offsetUtf16: span.start,
    );
  }

  int _targetIntent = 0;

  Future<void> playFromParagraph(
    BookSpeechContext book,
    BookLocator at, {
    bool prepareChapter = false,
  }) async {
    final intent = ++_targetIntent, generation = _generation;
    final lease = await book.source.acquire(book.key);
    try {
      final range = await BookParagraphCommands.resolve(book, at);
      if (_closed || intent != _targetIntent || generation != _generation) {
        return;
      }
      await playBook(book, from: range.start, prepareChapter: prepareChapter);
    } finally {
      await lease.release();
    }
  }

  Future<void> playFromWord(
    BookSpeechContext book,
    WordSelection selection, {
    bool prepareChapter = false,
  }) async {
    if (selection.start.key != book.key || !selection.canStart) {
      throw const BookFailure(BookError.unsupportedContent);
    }
    final intent = ++_targetIntent, generation = _generation;
    final source = book.source;
    if (source is! ParagraphNavigationSource) {
      throw const BookFailure(BookError.unsupportedContent);
    }
    final lease = await source.acquire(book.key);
    try {
      final current = await WordSelectionSource.resolve(
        source,
        selection.start,
      );
      if (!current.canStart ||
          current.text != selection.text ||
          current.start.blockId != selection.start.blockId ||
          current.start.offsetUtf16 != selection.start.offsetUtf16 ||
          current.end.offsetUtf16 != selection.end.offsetUtf16) {
        throw const BookFailure(BookError.invalidLocator);
      }
      if (_closed || intent != _targetIntent || generation != _generation) {
        return;
      }
      await playBook(
        book,
        from: current.start,
        exactFrom: true,
        prepareChapter: prepareChapter,
      );
    } finally {
      await lease.release();
    }
  }

  Future<bool> seekParagraph(BookLocator at) async {
    final book = _book;
    if (book == null || at.key != book.key) {
      throw const BookFailure(BookError.invalidLocator);
    }
    final intent = ++_targetIntent, generation = _generation;
    final lease = await book.source.acquire(book.key);
    try {
      final range = await BookParagraphCommands.resolve(book, at);
      if (_closed ||
          intent != _targetIntent ||
          generation != _generation ||
          _book != book) {
        return false;
      }
      final autoplay =
          state == PlaybackState.playing || state == PlaybackState.preparing;
      await playBook(
        book,
        from: range.start,
        autoplay: autoplay,
        prepareChapter: _prepareChapter,
      );
      return true;
    } finally {
      await lease.release();
    }
  }

  Future<bool> moveParagraph(bool forward) async {
    final book = _book, at = targetLocator;
    if (book == null || at == null || _closed) return false;
    final intent = ++_targetIntent, generation = _generation;
    bool cancelled() =>
        _closed ||
        intent != _targetIntent ||
        generation != _generation ||
        _book != book;
    final lease = await book.source.acquire(book.key);
    try {
      final destination = await BookParagraphCommands.neighbor(
        book,
        at,
        forward,
        cancelled,
      );
      if (cancelled()) return false;
      if (destination == null) {
        bookNotice = forward
            ? 'Fin du livre : aucun paragraphe suivant.'
            : 'Début du livre : aucun paragraphe précédent.';
        notifyListeners();
        return false;
      }
      return await seekParagraph(destination);
    } finally {
      await lease.release();
    }
  }

  int get retainedBookSegments => _bookSegments.length;
  List<SpeechSegment> _segments = [];
  final _outputs = <int, SpeechOutput>{};
  final _requests = <String, int>{};
  int _generation = 0, _index = 0;
  bool _loaded = false, _opened = false, _closed = false;
  Future<void>? _tail;
  Future<void>? _closing;
  String? get textId => _book?.wireId ?? _text?.id;
  SessionToken get _token => SessionToken('reader', _generation);
  SessionToken get _playerToken =>
      SessionToken('reader-player-$_index', _generation);
  bool _currentPlayer(SessionToken token) =>
      !_closed && token.matches(_playerToken);
  bool _current(SessionToken token) => !_closed && token.matches(_token);
  void _state(PlaybackState value) {
    if (!_closed) {
      state = value;
      notifyListeners();
    }
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final generation = _generation;
    final result = (_tail ?? Future<void>.value()).then((_) => action());
    _tail = result.catchError((Object failure) async {
      if (!_closed && generation == _generation) {
        error = failure is AppError
            ? failure
            : const AppError(ErrorCode.engineUnavailable);
        _state(PlaybackState.error);
        try {
          await _clear(_token);
        } catch (_) {
          /* Keep the public failure; allow a later retry. */
        }
      }
    });
    return _tail!;
  }

  Future<void> play(DemoText text, {Locator? from}) {
    if (from != null) text.validate(from);
    if (_voiceSuspended) {
      error = const AppError(ErrorCode.resourceInUse);
      _state(PlaybackState.error);
      return Future.value();
    }
    if (_closed ||
        (from == null &&
            _text?.id == text.id &&
            [PlaybackState.preparing, PlaybackState.playing].contains(state))) {
      return Future.value();
    }
    if (from == null && _text?.id == text.id && state == PlaybackState.paused) {
      return resume();
    }
    final previousText = _text;
    final previousBook = _book;
    final previousLocator = playedLocator;
    final previous = _token;
    _generation++;
    error = null;
    _text = text;
    _book = null;
    mediaTitle = mediaAuthor = mediaChapter = null;
    targetLocator = null;
    bookNotice = null;
    playedLocator = null;
    final token = _token;
    _state(PlaybackState.preparing);
    return _enqueue(() async {
      await _savePlayed(previousText, previousLocator, book: previousBook);
      await _clear(previous);
      if (!_current(token)) return;
      if (!_loaded) {
        await prepareEngine();
        _loaded = true;
      }
      if (!_current(token)) return;
      final segments = await segmenter.segment(text);
      if (!_current(token)) return;
      _segments = segments;
      _index = from == null ? 0 : _segmentIndex(text, segments, from);
      _segmentCursor = DemoSegmentCursor(segments, start: _index);
      if (_buffered) {
        _nextProduce = _index;
        _fillBuffer();
      } else {
        await _request(_index);
      }
    });
  }

  Future<void> playBook(
    BookSpeechContext book, {
    required BookLocator from,
    bool autoplay = true,
    bool exactFrom = false,
    bool prepareChapter = false,
  }) {
    if (_retiredBooks.contains(book.key)) {
      return Future.error(const BookFailure(BookError.operationInProgress));
    }
    book.toWire(
      from,
    ); // Reject foreign identity before changing the active session.
    if (_closed) return Future.value();
    if (_voiceSuspended) {
      error = const AppError(ErrorCode.resourceInUse);
      _state(PlaybackState.error);
      return Future.value();
    }
    final previousText = _text, previousLocator = playedLocator;
    final previousBook = _book, previous = _token;
    final quietState = state == PlaybackState.paused
        ? PlaybackState.paused
        : PlaybackState.stopped;
    _generation++;
    final token = _token;
    _text = null;
    _book = book;
    if (previousBook?.key != book.key) {
      mediaTitle = mediaAuthor = mediaChapter = null;
    }
    _segments = [];
    playedLocator = !autoplay && previousBook?.key == book.key
        ? previousLocator
        : null;
    targetLocator = from;
    bookNotice = null;
    error = null;
    _state(autoplay ? PlaybackState.preparing : quietState);
    return _enqueue(() async {
      await _savePlayed(previousText, previousLocator, book: previousBook);
      await _clear(previous);
      if (!_current(token)) return;
      if (positionError != null) {
        error = positionError;
        _state(PlaybackState.error);
        return;
      }
      await book.source.validateLocator(from);
      if (!_current(token) || !autoplay) return;
      if (!_loaded) {
        await prepareEngine();
        _loaded = true;
      }
      if (!_current(token)) return;
      await book.source.validateLocator(from);
      if (!_current(token)) return;
      final chapter = prepareChapter
          ? (await book.source.block(book.key, from.blockId)).chapterId
          : null;
      if (!_current(token)) return;
      _prepareChapter = prepareChapter;
      _segmentCursor = BookSegmentCursor(
        book,
        segmenter,
        from: from,
        exactFrom: exactFrom,
        onlyChapter: chapter,
      );
      _index = 0;
      if (_buffered) {
        _nextProduce = 0;
        _fillBuffer();
      } else {
        await _request(0);
      }
    });
  }

  int _segmentIndex(
    DemoText text,
    List<SpeechSegment> segments,
    Locator locator,
  ) {
    text.validate(locator);
    final paragraph = text.passages.indexWhere(
      (p) => p.id == locator.passageId,
    );
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final ordinal = text.passages.indexWhere(
        (p) => p.id == segment.start.passageId,
      );
      if (ordinal > paragraph ||
          (ordinal == paragraph &&
              segment.end.offsetUtf16 > locator.offsetUtf16)) {
        return i;
      }
    }
    // A locator at the very end replays the last segment instead of skipping it.
    return segments.length - 1;
  }

  Future<void> _clear(SessionToken token) async {
    await player.stop();
    _opened = false;
    await speech.cancel(token);
    await _producerWork;
    _producerDone = false;
    _producerBusy = false;
    _nextProduce = 0;
    _queued.clear();
    _pendingRetirement.clear();
    for (final release in _preparedLeases.values) {
      release();
    }
    _preparedLeases.clear();
    _prepareChapter = false;
    final handles = _outputs.values.map((o) => o.audioHandle).toList();
    if (releaseAudioBatch != null) {
      await releaseAudioBatch!(handles);
    } else {
      for (final handle in handles) {
        await discardAudio(handle);
      }
    }
    _outputs.clear();
    _requests.clear();
    _requestClocks.clear();
    await _segmentCursor?.close();
    _segmentCursor = null;
    _bookSegments.clear();
  }

  Future<bool> _acquireFocus(SessionToken token) async {
    if (state == PlaybackState.paused || !_current(token)) return false;
    final granted = await requestAudioFocus?.call() ?? true;
    if (!_current(token) || state == PlaybackState.paused) return false;
    if (!granted) {
      _state(PlaybackState.paused);
      return false;
    }
    return true;
  }

  Future<void> stop() {
    if (_closed) return Future.value();
    final previous = _token;
    final text = _text;
    final book = _book;
    final locator = playedLocator;
    ++_targetIntent;
    _generation++;
    _state(PlaybackState.stopped);
    return _enqueue(() async {
      await _savePlayed(text, locator, book: book);
      await _clear(previous);
    });
  }

  /// Explicit deletion boundary: retire only this book and never save its position.
  Future<void> releaseBook(ContentKey key) {
    if (_closed) return Future.value();
    _retiredBooks.add(key);
    final own = _book?.key == key, previous = _token;
    if (own) {
      _generation++;
      _book = null;
      targetLocator = null;
      bookNotice = null;
      _text = null;
      playedLocator = null;
      positionError = null;
      error = null;
      _state(PlaybackState.stopped);
    }
    return _enqueue(() async {
      try {
        if (own) await _clear(previous);
      } finally {
        _retiredBooks.remove(key);
      }
    });
  }

  Future<void> pause() {
    if (_closed ||
        ![PlaybackState.preparing, PlaybackState.playing].contains(state)) {
      return Future.value();
    }
    ++_targetIntent;
    _state(PlaybackState.paused);
    final text = _text;
    final book = _book;
    final locator = playedLocator;
    return _enqueue(() async {
      if (_opened) await player.pause();
      await _savePlayed(text, locator, book: book);
    });
  }

  Future<void> resume() {
    if (_voiceSuspended || _closed || state != PlaybackState.paused) {
      return Future.value();
    }
    if (_book != null && _segmentCursor == null && targetLocator != null) {
      return playBook(
        _book!,
        from: targetLocator!,
        prepareChapter: _prepareChapter,
      );
    }
    final token = _token;
    _state(PlaybackState.preparing);
    return _enqueue(() async {
      if (!_current(token)) return;
      if (!await _acquireFocus(token)) return;
      if (_opened) {
        await player.play();
      } else if (_outputs.containsKey(_index)) {
        if (_buffered) {
          await _maybeStartBuffer();
          _fillBuffer();
        } else {
          await _open();
        }
      }
    });
  }

  Future<void> previous() async {
    if (_book != null) {
      await moveParagraph(false);
    } else {
      await _move(_index > 0 ? _index - 1 : 0);
    }
  }

  Future<void> next() async {
    if (_book != null) {
      await moveParagraph(true);
    } else {
      await _move(_index + 1);
    }
  }

  Future<void> _move(int index) {
    if (_book != null) return Future.value();
    if (_voiceSuspended || _segments.isEmpty || _closed) return Future.value();
    final previous = _token;
    final text = _text;
    final locator = playedLocator;
    _generation++;
    final token = _token;
    _state(PlaybackState.preparing);
    return _enqueue(() async {
      await _savePlayed(text, locator);
      await _clear(previous);
      if (!_current(token)) return;
      _index = index;
      if (_index >= _segments.length) {
        _state(PlaybackState.completed);
        return;
      }
      _segmentCursor = DemoSegmentCursor(_segments, start: _index);
      if (_buffered) {
        _nextProduce = _index;
        _fillBuffer();
      } else {
        await _request(_index);
      }
    });
  }

  void _fillBuffer() {
    if (!_buffered ||
        _closed ||
        _producerDone ||
        _producerBusy ||
        _voiceSuspended ||
        _requests.isNotEmpty ||
        (!_prepareChapter && _outputs.length >= maxPreparedSegments) ||
        (!_prepareChapter && preparedAudioMs >= bufferTargetMs) ||
        _segmentCursor == null) {
      return;
    }
    final token = _token, index = _nextProduce;
    _producerBusy = true;
    _producerWork = () async {
      try {
        await _request(index);
      } catch (error, stack) {
        if (_current(token)) {
          unawaited(
            _enqueue(() async {
              Error.throwWithStackTrace(error, stack);
            }),
          );
        }
      } finally {
        _producerBusy = false;
        if (_current(token)) {
          unawaited(
            _enqueue(() async {
              if (!_current(token)) return;
              await _maybeStartBuffer();
              if (_requests.isEmpty && _nextProduce > index) _fillBuffer();
            }),
          );
        }
      }
    }();
  }

  Future<void> _maybeStartBuffer() async {
    if (_buffered &&
        _producerDone &&
        _outputs.isEmpty &&
        !_opened &&
        !_producerBusy &&
        _requests.isEmpty &&
        state == PlaybackState.preparing) {
      _state(PlaybackState.completed);
      return;
    }
    if (!_buffered ||
        _opened ||
        state == PlaybackState.paused ||
        _closed ||
        ![PlaybackState.preparing, PlaybackState.playing].contains(state) ||
        !_outputs.containsKey(_index)) {
      return;
    }
    if (_prepareChapter && !_producerDone) return;
    if (!_producerDone &&
        preparedAudioMs < initialBuffer.inMilliseconds &&
        _outputs.length < maxPreparedSegments) {
      return;
    }
    await _open();
  }

  Future<void> _request(int index) async {
    if (_buffered && _book == null && index >= _segments.length) {
      _producerDone = true;
      return;
    }

    if ((_book == null && index >= _segments.length) ||
        _outputs.containsKey(index) ||
        _requests.containsValue(index)) {
      return;
    }
    final token = _token;
    SpeechSegment? segment;
    if (_book != null && !_bookSegments.containsKey(index)) {
      segment = await _segmentCursor?.next();
      if (!_current(token)) return;
      if (segment == null) {
        if (_buffered) {
          await _segmentCursor?.close();
          _segmentCursor = null;
          _producerDone = true;
          return;
        }
        if (index == _index) {
          await _segmentCursor?.close();
          _segmentCursor = null;
          if (_current(token)) _state(PlaybackState.completed);
        }
        return;
      }
      if (_book != null) _bookSegments[index] = segment;
    }
    segment ??= _book != null ? _bookSegments[index]! : _segments[index];
    final id = 'r-$_generation-$index';
    _requests[id] = index;
    _requestClocks[id] = Stopwatch()..start();
    if (_buffered) _nextProduce = index + 1;
    await speech.synthesize(
      SpeechRequest(
        requestId: id,
        token: _token,
        start: segment.start,
        end: segment.end,
        text: segment.source,
        synthesisText: segment.synthesis,
        voiceId: voiceId,
        bundleId: bundleId,
        bookOwner: _book?.key,
      ),
    );
  }

  Future<void> _speechEvent(SpeechEvent event) async {
    if (!_current(event.token)) {
      if (event.output != null) await discardAudio(event.output!.audioHandle);
      return;
    }
    final index = _requests.remove(event.requestId);
    final requestClock = _requestClocks.remove(event.requestId);
    if (index == null) {
      if (event.output != null) await discardAudio(event.output!.audioHandle);
      return;
    }
    if (event.kind == SpeechEventKind.failed) {
      throw AppError(event.errorCode ?? ErrorCode.engineUnavailable);
    }
    if (event.kind != SpeechEventKind.completed) return;
    if (requestClock != null && event.output!.durationMs > 0) {
      final ratio = requestClock.elapsedMilliseconds / event.output!.durationMs;
      _warmRtf = _warmRtf == null ? ratio : _warmRtf! * 0.75 + ratio * 0.25;
    }
    final segment = _book != null ? _bookSegments[index]! : _segments[index];
    bool same(Locator a, Locator b) =>
        a.textId == b.textId &&
        a.corpusVersion == b.corpusVersion &&
        a.passageId == b.passageId &&
        a.offsetUtf16 == b.offsetUtf16;
    if (!same(event.output!.start, segment.start) ||
        !same(event.output!.end, segment.end)) {
      await discardAudio(event.output!.audioHandle);
      throw const AppError(ErrorCode.invalidMessage);
    }
    if (_prepareChapter &&
        (_outputs.length >= 2048 ||
            _outputs.values.fold<int>(0, (sum, o) => sum + o.byteSize) +
                    event.output!.byteSize >
                268435456)) {
      await discardAudio(event.output!.audioHandle);
      throw const AppError(ErrorCode.storageLimitExceeded);
    }
    if (_buffered && holdPreparedAudio != null) {
      final token = _token;
      final release = await holdPreparedAudio!(event.output!.audioHandle);
      if (!_current(token)) {
        release();
        return;
      }
      _preparedLeases[index] = release;
    }
    _outputs[index] = event.output!;
    if (_buffered) {
      final token = _token;
      if (_opened &&
          index > _index &&
          !_queued.contains(index) &&
          _queued.length < maxBufferedSegments) {
        await _playlist.append(
          event.output!.audioHandle,
          SessionToken('reader-player-$index', _generation),
        );
        if (!_current(token)) return;
        _queued.add(index);
      }
      await _maybeStartBuffer();
      _fillBuffer();
      if (!_closed) notifyListeners();
    } else if (index == _index && state != PlaybackState.paused) {
      await _open();
    }
  }

  Future<void> _open() async {
    final token = _token;
    if (!await _acquireFocus(token)) return;
    await player.open(_outputs[_index]!.audioHandle, _playerToken);
    if (!_current(token)) {
      await player.stop();
      return;
    }
    _opened = true;
    if (_buffered) {
      _queued.add(_index);
      final indexes = _outputs.keys.where((i) => i > _index).toList()..sort();
      for (final index in indexes.take(maxBufferedSegments - 1)) {
        await _playlist.append(
          _outputs[index]!.audioHandle,
          SessionToken('reader-player-$index', _generation),
        );
        if (!_current(token)) return;
        _queued.add(index);
      }
    }
    if (state == PlaybackState.paused) return;
    await player.play();
    if (_buffered) {
      _fillBuffer();
    } else if (_current(token) && _requests.isEmpty) {
      await _request(_index + 1);
    }
  }

  Future<void> _queuePrepared() async {
    if (!_buffered || !_opened) return;
    final token = _token;
    final indexes =
        _outputs.keys.where((i) => i > _index && !_queued.contains(i)).toList()
          ..sort();
    for (final index in indexes.take(maxBufferedSegments - _queued.length)) {
      await _playlist.append(
        _outputs[index]!.audioHandle,
        SessionToken('reader-player-$index', _generation),
      );
      if (!_current(token)) return;
      _queued.add(index);
    }
  }

  Future<void> _playerEvent(PlayerEvent event) async {
    if (!_currentPlayer(event.token)) return;
    switch (event.kind) {
      case PlayerEventKind.started:
        if (_buffered) {
          // A source-completed callback can precede the native current-source
          // update. Retire that source only once its successor really starts.
          for (final retired in List<SessionToken>.of(_pendingRetirement)) {
            await _playlist.retire(retired);
            if (!_currentPlayer(event.token)) return;
            _pendingRetirement.remove(retired);
          }
        }
        if (state != PlaybackState.paused) {
          playedLocator =
              (_book != null ? _bookSegments[_index]! : _segments[_index])
                  .start;
          if (_book != null) {
            final context = _book!;
            final locator = await context.toBook(playedLocator!);
            if (!_currentPlayer(event.token) ||
                _book != context ||
                state == PlaybackState.paused) {
              return;
            }
            targetLocator = locator;
          }
          _state(PlaybackState.playing);
          await _savePlayed(
            _text,
            playedLocator,
            isCurrent: () => _currentPlayer(event.token),
            book: _book,
          );
        }
      case PlayerEventKind.interrupted:
        _state(PlaybackState.paused);
        if (_opened) await player.pause();
      case PlayerEventKind.completed:
        if (_buffered) {
          final seamless =
              _queued.contains(_index + 1) &&
              _playlist.contains(
                SessionToken('reader-player-${_index + 1}', _generation),
              );
          if (seamless) {
            if (_playlist.isCurrent(
              SessionToken('reader-player-${_index + 1}', _generation),
            )) {
              await _playlist.retire(event.token);
            } else {
              _pendingRetirement.add(event.token);
            }
          } else {
            await player.stop();
            _opened = false;
            _queued.clear();
            _pendingRetirement.clear();
          }
          _queued.remove(_index);
          final old = _outputs.remove(_index);
          _preparedLeases.remove(_index)?.call();
          if (old != null) await discardAudio(old.audioHandle);
          _bookSegments.remove(_index);
          _index++;
          if (_producerDone &&
              _outputs.isEmpty &&
              _requests.isEmpty &&
              !_producerBusy) {
            _state(PlaybackState.completed);
            return;
          }
          if (state != PlaybackState.paused && !seamless) {
            _state(PlaybackState.preparing);
            await _maybeStartBuffer();
          }
          await _queuePrepared();
          _fillBuffer();
          return;
        }
        await player.stop();
        _opened = false;
        final old = _outputs.remove(_index);
        if (old != null) await discardAudio(old.audioHandle);
        _bookSegments.remove(_index);
        _index++;
        if (_book == null && _index == _segments.length) {
          _state(PlaybackState.completed);
          return;
        }
        if (state == PlaybackState.paused) return;
        _state(PlaybackState.preparing);
        if (_outputs.containsKey(_index)) {
          await _open();
        } else {
          await _request(_index);
        }
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    final token = _token;
    _generation++;
    _closed = true;
    await _speechSub.cancel();
    await _playerSub.cancel();
    await _tail;
    await _clear(token);
    await player.dispose();
    await speech.dispose();
    super.dispose();
  }
}
