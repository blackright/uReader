import 'package:flutter/foundation.dart';
import 'package:characters/characters.dart';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../../domain/bookmarks.dart';
import '../../domain/reader_experience.dart';
import 'book_reader_controller.dart';

class BookmarkEntry {
  const BookmarkEntry(
    this.bookmark,
    this.chapter,
    this.context, {
    this.exact = true,
  });
  final Bookmark bookmark;
  final String chapter, context;
  final bool exact;
}

class BookmarkCandidate {
  const BookmarkCandidate(this.locator, this.chapter, this.context);
  final BookLocator locator;
  final String chapter, context;
}

/// Visual navigation only. The optional follow boundary is unavailable until G1.
class BookmarkController extends ChangeNotifier {
  BookmarkController(this.reader, this.store, {this.suspendFollow});
  final BookReaderController reader;
  final BookmarkStore store;
  final VoidCallback? suspendFollow;
  List<BookmarkEntry> entries = [];
  BookmarkCandidate? proposal;
  BookmarkResolution? fallback;
  String? status, error;
  bool busy = false;
  BookmarkCursor? _next;
  bool get hasNext => _next != null;
  int _intent = 0;
  bool _closed = false;
  Future<void> Function()? _retry;
  bool _current(int i) => !_closed && !reader.isClosed && i == _intent;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  String _chapter(String id) =>
      reader.chapters.where((c) => c.id == id).firstOrNull?.title ??
      'Chapitre indisponible';
  Future<void> _run(
    Future<void> Function(int) work,
    Future<void> Function() retry,
  ) async {
    if (_closed || reader.isClosed || busy) return;
    final intent = ++_intent;
    busy = true;
    error = null;
    status = null;
    _notify();
    try {
      await work(intent);
      if (_current(intent)) _retry = null;
    } catch (_) {
      if (_current(intent)) {
        error =
            'Les signets n’ont pas pu être enregistrés ou chargés. Réessayez.';
        _retry = retry;
      }
    } finally {
      if (!_closed && intent == _intent) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> _list(int intent, {BookmarkCursor? after}) async {
    final page = await store.list(reader.book.key, after: after);
    final result = <BookmarkEntry>[];
    for (final mark in page.items) {
      if (!_current(intent)) return;
      final resolved = await store.resolve(mark);
      var context = 'Ce passage ne peut pas être retrouvé.';
      if (resolved.availability == BookmarkAvailability.exact) {
        final block = await reader.navigation!.block(
          mark.locator.key,
          mark.locator.blockId,
        );
        context = block.text.characters
            .skip(
              block.text
                  .substring(0, mark.locator.offsetUtf16)
                  .characters
                  .length,
            )
            .take(140)
            .toString();
        if (context.trim().isEmpty) {
          context = block.text.characters.take(140).toString();
        }
      }
      result.add(
        BookmarkEntry(
          mark,
          _chapter(mark.locator.chapterId),
          context,
          exact: resolved.availability == BookmarkAvailability.exact,
        ),
      );
    }
    if (_current(intent)) {
      entries = result;
      _next = page.next;
    }
  }

  Future<void> load({bool next = false}) {
    final cursor = next ? _next : null;
    if (!next) {
      proposal = null;
      fallback = null;
    }
    return _run((i) => _list(i, after: cursor), () => load(next: next));
  }

  Future<void> retry() async {
    final action = _retry;
    if (action != null) await action();
  }

  Future<void> _add(BookLocator at, int i) async {
    if (at.key != reader.book.key) {
      throw const BookFailure(BookError.invalidLocator);
    }
    final result = await store.add(at);
    if (!_current(i)) return;
    proposal = null;
    await _list(i);
    if (_current(i)) {
      status = result.created
          ? 'Signet ajouté.'
          : 'Ce passage possède déjà un signet.';
    }
  }

  Future<void> addAt(BookLocator at) =>
      _run((i) => _add(at, i), () => addAt(at));
  Future<void> addParagraph(BookLocator at) => _run((i) async {
    final source = reader.navigation;
    if (source is! ParagraphNavigationSource) {
      throw const BookFailure(BookError.unsupportedContent);
    }
    final range = await source.paragraphAt(at);
    if (!_current(i)) return;
    await _add(range.start, i);
  }, () => addParagraph(at));
  Future<void> addVisible() => _run((i) async {
    final source = reader.navigation;
    if (source == null) throw const BookFailure(BookError.unsupportedContent);
    var at = reader.visible;
    final page = reader.experience.mode == ReaderMode.paged
        ? reader.pagination?.current
        : null;
    if (page != null) {
      at = null;
      for (final f in page.fragments) {
        if (!f.coverageOnly &&
            f.block.speechEligible &&
            f.block.text
                .substring(f.startUtf16, f.endUtf16)
                .trim()
                .isNotEmpty) {
          at = f.locator;
          break;
        }
      }
    }
    if (at != null) {
      final block = await source.block(at.key, at.blockId);
      if (block.speechEligible && block.text.trim().isNotEmpty) {
        await _add(at, i);
        return;
      }
    }
    final base = reader.visible;
    if (base == null) throw const BookFailure(BookError.invalidLocator);
    final block = await source.block(base.key, base.blockId);
    final end = reader.chapters.fold<int>(
      0,
      (v, c) => v > c.firstBlockOrdinal + c.blockCount
          ? v
          : c.firstBlockOrdinal + c.blockCount,
    );
    for (final direction in [1, -1]) {
      for (var step = 1; step <= 128 && _current(i); step++) {
        final ordinal = block.ordinal + direction * step;
        if (ordinal < 0 || ordinal >= end) break;
        final window = await source.window(
          base.key,
          1,
          after: BookCursor(key: base.key, generation: 1, nextOrdinal: ordinal),
          maxBlocks: 1,
          maxUnits: 8192,
        );
        final b = window.blocks.single;
        if (!b.speechEligible || b.text.trim().isEmpty) continue;
        var locator = BookLocator(
          key: b.key,
          chapterId: b.chapterId,
          blockId: b.id,
          offsetUtf16: 0,
        );
        if (source is ParagraphNavigationSource) {
          locator = (await source.paragraphAt(locator)).start;
        }
        final text = await source.block(locator.key, locator.blockId);
        if (_current(i)) {
          proposal = BookmarkCandidate(
            locator,
            _chapter(locator.chapterId),
            text.text.characters.take(140).toString(),
          );
          status = 'Cette page ne contient pas de passage texte principal. Ajouter le passage voisin proposé ?';
        }
        return;
      }
    }
    if (_current(i)) status = 'Aucun passage texte proche. Choisissez un paragraphe dans le lecteur.';
  }, addVisible);
  Future<void> confirmProposal() async {
    final chosen = proposal;
    if (chosen != null) await addAt(chosen.locator);
  }

  Future<void> remove(Bookmark mark) => _run((i) async {
    if (mark.locator.key != reader.book.key) {
      throw const BookFailure(BookError.invalidLocator);
    }
    await store.remove(mark.id, reader.book.key);
    if (!_current(i)) return;
    await _list(i);
    if (_current(i)) status = 'Signet supprimé.';
  }, () => remove(mark));
  Future<bool> open(Bookmark mark) async {
    var opened = false;
    await _run(
      (i) async {
        if (mark.locator.key != reader.book.key) {
          throw const BookFailure(BookError.invalidLocator);
        }
        final resolution = await store.resolve(mark);
        if (!_current(i)) return;
        if (resolution.availability != BookmarkAvailability.exact) {
          fallback = resolution;
          status = 'Ce signet ne peut pas être retrouvé exactement. Choisissez un repli explicite.';
          return;
        }
        suspendFollow?.call();
        await reader.go(resolution.locator!);
        if (_current(i)) {
          opened = reader.error == null;
          fallback = null;
          if (!opened) throw const BookFailure(BookError.sourceUnavailable);
        }
      },
      () async {
        await open(mark);
      },
    );
    return opened;
  }

  Future<bool> openFallback({bool chapter = true}) async {
    final choice = fallback;
    var opened = false;
    if (choice == null) return false;
    await _run(
      (i) async {
        final target = chapter
            ? reader.chapters.where((c) => c.id == choice.chapterId).firstOrNull
            : null;
        if (chapter && target == null) {
          status = 'Ce chapitre n’est pas disponible. Vous pouvez ouvrir le début du livre.';
          return;
        }
        final selected = target ?? reader.chapters.firstOrNull;
        if (selected == null) {
          throw const BookFailure(BookError.sourceUnavailable);
        }
        suspendFollow?.call();
        await reader.chapter(selected.id);
        if (_current(i)) {
          opened = reader.error == null;
          if (!opened) throw const BookFailure(BookError.sourceUnavailable);
          fallback = null;
          status = 'Repli ouvert ; il ne s’agit pas du passage exact.';
        }
      },
      () async {
        await openFallback(chapter: chapter);
      },
    );
    return opened;
  }

  @override
  void dispose() {
    _closed = true;
    ++_intent;
    super.dispose();
  }
}
