import 'package:flutter/foundation.dart';
import 'package:characters/characters.dart';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../listening/book_segment_cursor.dart';
import '../listening/content_source_adapter.dart';

class ParagraphChoice {
  const ParagraphChoice(this.locator, this.excerpt);
  final BookLocator locator;
  final String excerpt;
}

/// Bounded target discovery: one page of scalar ranges and short excerpts, no audio commands.
class ContentTargetController extends ChangeNotifier {
  ContentTargetController(this.key, this.source);
  final ContentKey key;
  final ParagraphNavigationSource source;
  List<BookChapter> chapters = [];
  BookChapter? chapter;
  List<ParagraphChoice> choices = [];
  ParagraphChoice? selected;
  double? actualProgress;
  int? nextOrdinal;
  bool loading = false;
  String? error;
  int _intent = 0;
  bool _closed = false;
  bool _current(int i) => !_closed && i == _intent;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> initialize({BookLocator? initial}) async {
    try {
      chapters = await source.chapters(key);
      if (_closed) return;
      final first =
          chapters.where((c) => c.id == initial?.chapterId).firstOrNull ??
          chapters.firstOrNull;
      if (first != null) await selectChapter(first);
    } catch (_) {
      if (!_closed) {
        error = 'Les passages ne peuvent pas être chargés.';
        _notify();
      }
    }
  }

  Future<void> selectChapter(BookChapter c) async {
    chapter = c;
    selected = null;
    actualProgress = null;
    await load(c.firstBlockOrdinal);
  }

  Future<void> load(int ordinal) async {
    final intent = ++_intent;
    loading = true;
    error = null;
    _notify();
    try {
      final page = await source.paragraphs(
        key,
        1,
        after: BookCursor(key: key, generation: 1, nextOrdinal: ordinal),
        limit: 25,
      );
      final result = <ParagraphChoice>[];
      for (final range in page.paragraphs) {
        if (!_current(intent)) return;
        if (range.start.chapterId != chapter?.id) break;
        if (!range.speechEligible) continue;
        final block = await source.block(key, range.start.blockId);
        result.add(
          ParagraphChoice(
            range.start,
            block.text.characters.take(140).toString(),
          ),
        );
      }
      if (!_current(intent)) return;
      choices = result;
      nextOrdinal = page.paragraphs.any((r) => r.start.chapterId != chapter?.id)
          ? null
          : page.nextOrdinal;
    } catch (_) {
      if (_current(intent)) {
        error = 'Ces passages ne sont pas disponibles. Réessayez.';
      }
    } finally {
      if (_current(intent)) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> choose(BookLocator at) async {
    final intent = ++_intent;
    loading = true;
    error = null;
    _notify();
    try {
      final range = await BookParagraphCommands.resolve(
        BookSpeechContext(key, source),
        at,
      );
      final block = await source.block(key, range.start.blockId),
          progress = await source.progress(range.start);
      if (!_current(intent)) return;
      selected = ParagraphChoice(
        range.start,
        block.text.characters.take(180).toString(),
      );
      actualProgress = progress.$2 <= 0
          ? null
          : (progress.$1 / progress.$2).clamp(0.0, 1.0);
    } catch (_) {
      if (_current(intent)) {
        selected = null;
        error = 'Ce passage ne contient pas de texte narrable. Choisissez un autre passage.';
      }
    } finally {
      if (_current(intent)) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> selectProgress(double fraction) async {
    if (!fraction.isFinite || fraction < 0 || fraction > 1) return;
    final intent = ++_intent;
    loading = true;
    selected = null;
    error = null;
    _notify();
    try {
      final total = chapters.fold<int>(0, (n, c) => n + c.textUnits);
      if (total <= 0) throw const BookFailure(BookError.invalidLocator);
      final wanted = (fraction * total).floor().clamp(0, total - 1);
      var before = 0;
      BookChapter? target;
      for (final c in chapters) {
        if (wanted < before + c.textUnits) {
          target = c;
          break;
        }
        before += c.textUnits;
      }
      if (target == null) throw const BookFailure(BookError.invalidLocator);
      var ordinal = target.firstBlockOrdinal;
      final end = ordinal + target.blockCount;
      while (ordinal < end && _current(intent)) {
        final window = await source.window(
          key,
          1,
          after: BookCursor(key: key, generation: 1, nextOrdinal: ordinal),
          maxBlocks: 16,
          maxUnits: 65536,
        );
        for (final block in window.blocks) {
          if (block.ordinal >= end) break;
          if (wanted < before + block.text.length) {
            if (!_current(intent)) return;
            chapter = target;
            await choose(
              BookLocator(
                key: key,
                chapterId: block.chapterId,
                blockId: block.id,
                offsetUtf16: 0,
              ),
            );
            return;
          }
          before += block.text.length;
        }
        ordinal = window.blocks.last.ordinal + 1;
        await Future<void>.delayed(Duration.zero);
      }
    } catch (_) {
      if (_current(intent)) {
        error =
            'Cette cible ne peut pas être retrouvée. Choisissez un chapitre.';
      }
    } finally {
      if (_current(intent)) {
        loading = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    ++_intent;
    super.dispose();
  }
}
