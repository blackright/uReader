import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../../domain/reader_experience.dart';
import '../listening/playback_coordinator.dart';

class PlayerBook {
  const PlayerBook(this.book, {this.coverResource});
  final Book book;
  final String? coverResource;
}

/// Application-owned projection. Widgets never own engines, caches or audio leases.
class PlayerPresenter extends ChangeNotifier {
  PlayerPresenter({
    required this.owner,
    required this.source,
    required this.lookup,
    required this.preferences,
  }) {
    owner.addListener(_changed);
  }
  final PlaybackCoordinator owner;
  final ParagraphNavigationSource source;
  final Future<PlayerBook?> Function(ContentKey) lookup;
  final ExperiencePreferenceStore preferences;
  PlayerBook? details;
  Book? get book => details?.book;
  List<BookChapter> chapters = [];
  BookLocator? target, heard;
  double? targetProgress, heardProgress;
  String? problem;
  String get chapterTitle =>
      chapters
          .where((c) => c.id == (target ?? heard)?.chapterId)
          .firstOrNull
          ?.title ??
      'Chapitre en préparation';
  PlaybackState get state => owner.state;
  String get status => switch (state) {
    PlaybackState.preparing => owner.preparationStatus,
    PlaybackState.playing => 'Lecture en cours',
    PlaybackState.paused => 'Lecture en pause',
    PlaybackState.stopped => 'Lecture arrêtée',
    PlaybackState.completed => owner.completionStatus,
    PlaybackState.error => owner.error?.message ?? 'Lecture audio indisponible',
  };
  String? get notice =>
      problem ?? owner.bookNotice ?? owner.positionError?.message;
  bool get miniVisible =>
      owner.bookKey != null &&
      [
        PlaybackState.preparing,
        PlaybackState.playing,
        PlaybackState.paused,
      ].contains(state);
  AudioPresentation presentation = AudioPresentation.full;
  ExperiencePreferences? _preferences;
  int _revision = 0, _preferenceIntent = 0;
  int? _seenGeneration;
  bool _closed = false;
  Future<void> _saveTail = Future.value();
  Future<void> flush() => _saveTail;
  Future<void> initialize() async {
    final intent = _preferenceIntent;
    try {
      final values = await preferences.read();
      if (_closed || intent != _preferenceIntent) return;
      _preferences = values;
      presentation = _preferences!.presentation;
    } catch (_) {
      if (!_closed) problem = 'Les réglages audio ne peuvent pas être chargés.';
    }
    if (!_closed) await refresh();
  }

  void _changed() {
    if (!_closed) {
      if (_seenGeneration != owner.sessionGeneration) {
        problem = null;
        _seenGeneration = owner.sessionGeneration;
      }
      if (details?.book.key != owner.bookKey) {
        details = null;
        chapters = [];
        target = heard = null;
        targetProgress = heardProgress = null;
      }
      notifyListeners();
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    final revision = ++_revision,
        key = owner.bookKey,
        generation = owner.sessionGeneration;
    bool current() =>
        !_closed &&
        revision == _revision &&
        generation == owner.sessionGeneration &&
        key == owner.bookKey;
    if (key == null) {
      details = null;
      chapters = [];
      target = heard = null;
      targetProgress = heardProgress = null;
      if (!_closed) notifyListeners();
      return;
    }
    final chosen = owner.targetLocator,
        played = owner.playedLocator,
        context = owner.bookContext;
    try {
      final metadata = details?.book.key == key ? details : await lookup(key);
      if (!current()) return;
      final headings = details?.book.key == key
          ? chapters
          : await source.chapters(key);
      final actual = played == null || context == null
          ? null
          : await context.toBook(played);
      double? percent((int, int)? p) =>
          p == null || p.$2 <= 0 ? null : (p.$1 / p.$2).clamp(0.0, 1.0);
      final chosenProgress = chosen == null
          ? null
          : await source.progress(chosen);
      final actualProgress = actual == null
          ? null
          : await source.progress(actual);
      if (!current()) return;
      details = metadata;
      chapters = headings;
      target = chosen;
      heard = actual;
      targetProgress = percent(chosenProgress);
      heardProgress = percent(actualProgress);
      if (metadata != null) {
        owner.publishBookMetadata(
          key,
          title: metadata.book.title,
          author: metadata.book.authors.join(', '),
          chapter: chapterTitle,
        );
      }
      notifyListeners();
    } catch (_) {
      if (current()) {
        problem = 'Les informations de cette lecture sont indisponibles.';
        notifyListeners();
      }
    }
  }

  Future<void> changePresentation(AudioPresentation value) {
    final intent = ++_preferenceIntent;
    final task = _saveTail.then((_) async {
      if (_closed) return;
      try {
        // Read latest values: changing the player must not reset typography saved elsewhere.
        final old = await preferences.read();
        final next = ExperiencePreferences(
          mode: old.mode,
          lineHeight: old.lineHeight,
          margins: old.margins,
          followEnabled: old.followEnabled,
          presentation: value,
        );
        await preferences.save(next);
        if (_closed || intent != _preferenceIntent) return;
        _preferences = next;
        presentation = value;
        problem = null;
        notifyListeners();
      } catch (_) {
        if (!_closed && intent == _preferenceIntent) {
          problem = 'Présentation non enregistrée. Réessayez.';
          notifyListeners();
        }
      }
    });
    _saveTail = task;
    return task;
  }

  Future<void> playPause() async {
    final generation = owner.sessionGeneration;
    try {
      if (state == PlaybackState.playing || state == PlaybackState.preparing) {
        await owner.pause();
      } else if (state == PlaybackState.paused) {
        await owner.resume();
      } else if (owner.bookContext != null && owner.targetLocator != null) {
        await owner.playFromParagraph(owner.bookContext!, owner.targetLocator!);
      }
    } catch (_) {
      if (generation == owner.sessionGeneration) {
        _failure();
      }
    }
  }

  Future<void> move(bool forward) async {
    final generation = owner.sessionGeneration;
    try {
      await owner.moveParagraph(forward);
    } catch (_) {
      if (generation == owner.sessionGeneration) {
        _failure();
      }
    }
  }

  Future<void> seek(BookLocator locator, {required int generation}) async {
    if (_closed) return;
    if (generation != owner.sessionGeneration || locator.key != owner.bookKey) {
      problem = 'La session a changé. Choisissez à nouveau le passage.';
      notifyListeners();
      return;
    }
    try {
      await owner.seekParagraph(locator);
    } catch (_) {
      if (generation == owner.sessionGeneration) {
        _failure();
      }
    }
  }

  void _failure() {
    if (!_closed) {
      problem = 'Ce passage audio n’est pas disponible. Réessayez.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    ++_revision;
    owner.removeListener(_changed);
    super.dispose();
  }
}
