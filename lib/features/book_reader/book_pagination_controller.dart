import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../../domain/pagination.dart';
import 'book_paginator.dart';
import 'reader_layout.dart';

/// Owns visual pagination only. Source windows and retained pages are bounded;
/// boundaries live in the existing derived SQLite index, never a book-sized list.
class BookPaginationController extends ChangeNotifier {
  BookPaginationController({
    required this.key,
    required this.source,
    required this.index,
    required this.onVisible,
  });
  final ContentKey key;
  final BookNavigationSource source;
  final PageIndexStore index;
  final void Function(BookLocator, BookBlock) onVisible;
  final String _scope = List.generate(
    4,
    (_) =>
        Random.secure().nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
  ).join();
  int generation = 0;
  int? pageNumber, total;
  int prefixPages = 0;
  BookPage? previous, current, next;
  ReaderLayout? layout;
  PaginationError? error;
  bool calculating = false, navigating = false;
  bool _closed = false;
  ContentLease? _lease;
  String? _handle;
  Future<void> _work = Future.value(), _navigation = Future.value();
  Future<void>? _closeFuture;
  int get retainedPages =>
      [previous, current, next].whereType<BookPage>().length;
  void _notify() {
    if (!_closed) notifyListeners();
  }

  bool _stale(int g) => _closed || g != generation;

  Stream<BookBlock> _blocks(int first, int g) async* {
    var ordinal = first;
    while (!_stale(g)) {
      final window = await source.window(
        key,
        g,
        after: BookCursor(key: key, generation: g, nextOrdinal: ordinal),
        maxBlocks: 1,
        maxUnits: 8192,
      );
      if (_stale(g)) return;
      if (window.key != key ||
          window.generation != g ||
          window.blocks.length > 1) {
        throw const PaginationFailure(PaginationError.invalidIndex);
      }
      if (window.blocks.isEmpty) {
        if (!window.done) {
          throw const PaginationFailure(PaginationError.invalidIndex);
        }
        return;
      }
      final block = window.blocks.single;
      if (block.ordinal != ordinal) {
        throw const PaginationFailure(PaginationError.invalidIndex);
      }
      yield block;
      if (window.done) return;
      final cursor = window.next;
      if (cursor == null || cursor.nextOrdinal != ordinal + 1) {
        throw const PaginationFailure(PaginationError.invalidIndex);
      }
      ordinal++;
    }
  }

  /// Starts with a local preview at the saved block while the global prefix is
  /// calculated. Its local ordinal is never presented as a global page number.
  Future<void> configure(ReaderLayout value, BookLocator target) async {
    final g = ++generation;
    final oldWork = _work, oldNavigation = _navigation;
    current = previous = next = null;
    pageNumber = total = null;
    prefixPages = 0;
    error = null;
    calculating = true;
    navigating = false;
    layout = value;
    _notify();
    await oldWork;
    await oldNavigation;
    if (_stale(g)) return;
    if (_handle != null) await _discard(_handle!);
    if (_stale(g)) return;
    _handle = null;
    _work = _run(value, target, g);
    // Configuration returns after work starts; close() awaits its completion.
  }

  Future<void> _run(ReaderLayout value, BookLocator target, int g) async {
    String? handle;
    try {
      _lease ??= await source.acquire(key);
      if (_stale(g)) return;
      await source.validateLocator(target);
      final block = await source.block(key, target.blockId);
      if (_stale(g)) return;
      final point = PagePoint(
        block.ordinal,
        target.offsetUtf16 == block.text.length && block.text.isNotEmpty
            ? target.offsetUtf16 - 1
            : target.offsetUtf16,
      );
      final preview = StreamIterator(
        BookPaginator(value).paginate(
          _blocks(max(0, block.ordinal - 1), g),
          from: PagePoint(max(0, block.ordinal - 1), 0),
          cancelled: () => _stale(g),
        ),
      );
      try {
        while (await preview.moveNext()) {
          if (_stale(g)) return;
          final page = preview.current;
          if (page.start.compareTo(point) <= 0 &&
              page.end.compareTo(point) > 0) {
            current = page;
            _notify();
            break;
          }
        }
      } finally {
        await preview.cancel();
      }
      if (_stale(g)) return;
      final digest = await index.sourceDigest(key);
      // System fallback font identities are unresolved: this index is scoped to
      // this controller/configuration and is removed when closed/replaced.
      final fingerprint = value.fingerprintForSession(
        digest,
        key.version,
        '$_scope:$g',
      );
      handle = await index.begin(key, fingerprint.value, g);
      if (_stale(g)) return;
      _handle = handle;
      var found = false;
      BookPage? preceding;
      final batch = <PageBoundary>[];
      await for (final page in BookPaginator(
        value,
      ).paginate(_blocks(0, g), cancelled: () => _stale(g))) {
        if (_stale(g)) return;
        if (!found &&
            page.start.compareTo(point) <= 0 &&
            page.end.compareTo(point) > 0) {
          found = true;
          previous = preceding;
          preceding = null;
          current = page;
          pageNumber = page.ordinal + 1;
          next = null;
        } else if (found &&
            current != null &&
            page.ordinal == current!.ordinal + 1) {
          next = page;
        }
        if (!found) preceding = page;
        batch.add(page.boundary);
        if (batch.length == 128 ||
            (found && page.ordinal <= current!.ordinal + 1)) {
          await index.append(handle, batch, generation: g, complete: false);
          prefixPages += batch.length;
          batch.clear();
          if (_stale(g)) return;
          _notify();
        }
      }
      if (_stale(g)) return;
      await index.append(handle, batch, generation: g, complete: true);
      prefixPages += batch.length;
      total = prefixPages;
      calculating = false;
      if (!found) error = PaginationError.invalidIndex;
      _notify();
    } on PaginationFailure catch (failure) {
      if (!_stale(g)) {
        error = failure.code;
        calculating = false;
        _notify();
      }
    } catch (_) {
      if (!_stale(g)) {
        error = PaginationError.invalidIndex;
        calculating = false;
        _notify();
      }
    } finally {
      if (handle != null && _stale(g)) await _discard(handle);
    }
  }

  Future<BookPage?> _page(int ordinal, int g) async {
    if (ordinal < 0) return null;
    final handle = _handle, value = layout;
    if (handle == null || value == null || _stale(g)) return null;
    final boundaries = await index.boundaries(handle, ordinal, limit: 1);
    if (_stale(g) ||
        boundaries.isEmpty ||
        boundaries.single.ordinal != ordinal) {
      return null;
    }
    final boundary = boundaries.single;
    final pages = StreamIterator(
      BookPaginator(value).paginate(
        _blocks(max(0, boundary.start.ordinal - 1), g),
        from: boundary.start,
        startPage: ordinal,
        cancelled: () => _stale(g),
      ),
    );
    try {
      if (!await pages.moveNext() || _stale(g)) return null;
      if (pages.current.end != boundary.end) {
        throw const PaginationFailure(PaginationError.invalidIndex);
      }
      return pages.current;
    } finally {
      await pages.cancel();
    }
  }

  Future<void> turn(bool forward) {
    if (_closed || navigating || pageNumber == null || current == null) {
      return Future.value();
    }
    navigating = true;
    final g = generation;
    _notify();
    return _navigation = () async {
      try {
        final old = current!;
        final ordinal = old.ordinal + (forward ? 1 : -1);
        if (ordinal < 0) return;
        final page = (forward ? next : previous) ?? await _page(ordinal, g);
        if (_stale(g) || page == null) return;
        current = page;
        pageNumber = page.ordinal + 1;
        previous = forward ? old : null;
        next = forward ? null : old;
        onVisible(page.fragments.first.locator, page.fragments.first.block);
        _notify();
        final neighbor = await _page(ordinal + (forward ? 1 : -1), g);
        if (_stale(g)) return;
        if (forward) {
          // The scanner may have supplied this neighbor while the disk lookup
          // was awaiting publication of its batch. Do not erase that newer page.
          if (neighbor != null || next?.ordinal != ordinal + 1) next = neighbor;
        } else {
          previous = neighbor;
        }
      } on PaginationFailure catch (failure) {
        if (!_stale(g)) error = failure.code;
      } catch (_) {
        if (!_stale(g)) error = PaginationError.invalidIndex;
      } finally {
        if (!_stale(g)) {
          navigating = false;
          _notify();
        }
      }
    }();
  }

  /// Navigate within the existing derived index, without restarting pagination.
  /// Missing unpublished boundaries are retried by the caller on a later update.
  Future<bool> followTo(
    BookLocator target, {
    required bool Function() stillCurrent,
  }) {
    if (_closed ||
        navigating ||
        target.key != key ||
        _handle == null ||
        pageNumber == null ||
        !stillCurrent()) {
      return Future.value(false);
    }
    final g = generation, handle = _handle!;
    navigating = true;
    var moved = false;
    final result = () async {
      try {
        final block = await source.block(key, target.blockId);
        target.validate(block);
        if (_stale(g) || !stillCurrent()) return false;
        final point = PagePoint(block.ordinal, target.offsetUtf16);
        var low = 0, high = prefixPages - 1;
        int? found;
        while (low <= high) {
          final mid = (low + high) ~/ 2;
          final rows = await index.boundaries(handle, mid, limit: 1);
          if (_stale(g) || !stillCurrent() || rows.length != 1) return false;
          final boundary = rows.single;
          if (point.compareTo(boundary.start) < 0) {
            high = mid - 1;
          } else if (point.compareTo(boundary.end) >= 0) {
            low = mid + 1;
          } else {
            found = mid;
            break;
          }
        }
        if (found == null) return false;
        final page = await _page(found, g);
        if (_stale(g) || !stillCurrent() || page == null) return false;
        final before = await _page(found - 1, g),
            after = await _page(found + 1, g);
        if (_stale(g) || !stillCurrent()) return false;
        current = page;
        previous = before;
        next = after;
        pageNumber = page.ordinal + 1;
        moved = true;
        onVisible(target, block);
        return true;
      } catch (_) {
        // Follow metadata or an unpublished index cannot break visual consultation.
        return false;
      } finally {
        if (!_stale(g)) {
          navigating = false;
          if (moved) _notify();
        }
      }
    }();
    _navigation = result.then<void>((_) {});
    return result;
  }

  Future<void> _discard(String handle) async {
    try {
      await index.invalidate(handle);
    } catch (_) {
      // A failed derived-cache cleanup must not retain a content lease or block
      // visual reading. The session-scoped fingerprint is never reused.
    }
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> suspend() async {
    final g = ++generation;
    await _work;
    await _navigation;
    if (_stale(g)) return;
    if (_handle != null) await _discard(_handle!);
    if (_stale(g)) return;
    _handle = null;
    final lease = _lease;
    _lease = null;
    await lease?.release();
    if (_stale(g)) return;
    current = previous = next = null;
    pageNumber = total = null;
    calculating = false;
    _notify();
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    generation++;
    await _work;
    await _navigation;
    if (_handle != null) await _discard(_handle!);
    await _lease?.release();
    _lease = null;
    current = previous = next = null;
    super.dispose();
  }
}
