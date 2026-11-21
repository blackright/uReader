import 'dart:async';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../../domain/paragraph_index.dart';
import '../../domain/pagination.dart';
import 'reader_layout.dart';

class BookPaginator {
  BookPaginator(this.layout);
  final ReaderLayout layout;
  int maximumBatchMicros = 0;
  Stream<
    ({
      BookBlock block,
      bool paragraphStart,
      bool paragraphEnd,
      PageTextContext? context,
    })
  >
  _slices(Stream<BookBlock> source, {PagePoint? from}) async* {
    final iterator = StreamIterator(source);
    final index = ParagraphIndex();
    try {
      if (!await iterator.moveNext()) return;
      var current = iterator.current;
      var first = true;
      while (true) {
        final hasNext = await iterator.moveNext();
        final next = hasNext ? iterator.current : null;
        final continuation =
            next != null &&
            index.identity(current) == index.identity(next) &&
            current.key == next.key;
        if (continuation &&
            (index.slice(next) != index.slice(current) + 1 ||
                next.ordinal != current.ordinal + 1 ||
                next.kind != current.kind ||
                next.speechEligible != current.speechEligible)) {
          throw const PaginationFailure(PaginationError.invalidIndex);
        }
        final join =
            continuation &&
            !current.isIdentifiedNote &&
            !index.validTextBoundary(
              current.text + next.text,
              current.text.length,
            );
        if (first && from == null && index.slice(current) != 0) {
          throw const PaginationFailure(PaginationError.invalidIndex);
        }
        if (join) {
          final second = next;
          final context = PageTextContext([current, second]);
          final start = index.slice(current) == 0;
          final firstBlock = current;
          final hasAfter = await iterator.moveNext();
          final after = hasAfter ? iterator.current : null;
          final continues =
              after != null &&
              index.identity(second) == index.identity(after) &&
              second.key == after.key;
          if (continues &&
              (index.slice(after) != index.slice(second) + 1 ||
                  after.ordinal != second.ordinal + 1 ||
                  after.kind != second.kind ||
                  after.speechEligible != second.speechEligible)) {
            throw const PaginationFailure(PaginationError.invalidIndex);
          }
          if (continues &&
              !index.validTextBoundary(
                second.text + after.text,
                second.text.length,
              )) {
            throw const PaginationFailure(PaginationError.unsafeSliceBoundary);
          }
          if (from == null || second.ordinal >= from.ordinal) {
            yield (
              block: firstBlock,
              context: context,
              paragraphStart: start,
              paragraphEnd: !continues,
            );
          }
          if (!hasAfter) break;
          current = after!;
        } else {
          if (from == null || current.ordinal >= from.ordinal) {
            yield (
              block: current,
              context: null,
              paragraphStart: index.slice(current) == 0,
              paragraphEnd: !continuation,
            );
          }
          if (!hasNext) break;
          current = next!;
        }
        first = false;
      }
    } finally {
      await iterator.cancel();
    }
  }

  Stream<BookPage> paginate(
    Stream<BookBlock> source, {
    bool Function()? cancelled,
    PagePoint? from,
    int startPage = 0,
  }) async* {
    var fragments = <PageFragment>[],
        height = 0.0,
        ordinal = startPage,
        expected = from?.ordinal ?? 0;
    ContentKey? key;
    var residentUnits = 0, blocks = 0;
    var started = false;
    final watch = Stopwatch()..start();
    void check() {
      if (cancelled?.call() ?? false) {
        throw const PaginationFailure(PaginationError.cancelled);
      }
    }

    void append(PageFragment f) {
      if (fragments.isNotEmpty &&
          fragments.last.block.id == f.block.id &&
          f.context == null &&
          fragments.last.context == null &&
          !f.atomic &&
          !fragments.last.atomic) {
        final old = fragments.removeLast();
        fragments.add(
          PageFragment(
            block: f.block,
            startUtf16: old.startUtf16,
            endUtf16: f.endUtf16,
            clipTop: old.clipTop,
            textHeight: old.textHeight + f.textHeight,
            fullTextHeight: f.fullTextHeight,
            leading: old.leading,
            trailing: f.trailing,
            paragraphStart: old.paragraphStart,
          ),
        );
      } else {
        fragments.add(f);
      }
      height += f.height;
    }

    void pauseWatch() {
      if (watch.elapsedMicroseconds > maximumBatchMicros) {
        maximumBatchMicros = watch.elapsedMicroseconds;
      }
      watch.stop();
    }

    await for (final slice in _slices(source, from: from)) {
      final b = slice.block;
      final context = slice.context;
      final sourceBlocks = context?.blocks ?? [b];
      final text = context?.text ?? b.text;
      if (!started &&
          from != null &&
          b.ordinal < expected &&
          sourceBlocks.last.ordinal >= expected) {
        expected = b.ordinal;
      }
      started = true;
      watch
        ..reset()
        ..start();
      check();
      if (b.ordinal != expected || (key != null && key != b.key)) {
        throw const PaginationFailure(PaginationError.invalidIndex);
      }
      key ??= b.key;
      expected += sourceBlocks.length;
      if (fragments.isNotEmpty &&
          (blocks >= 16 || residentUnits + text.length > 16384)) {
        pauseWatch();
        yield BookPage(ordinal++, fragments);
        watch
          ..reset()
          ..start();
        check();
        fragments = [];
        height = 0;
        residentUnits = 0;
        blocks = 0;
      }
      blocks += sourceBlocks.length;
      residentUnits += text.length;
      pauseWatch();
      final measured = await layout.measureCooperatively(
        b,
        context: context,
        cancelled: () => cancelled?.call() ?? false,
        onBatch: (micros) {
          if (micros > maximumBatchMicros) maximumBatchMicros = micros;
        },
      );
      watch
        ..reset()
        ..start();
      check();
      if (measured.atomic) {
        if (measured.height > layout.height + .001) {
          throw const PaginationFailure(PaginationError.viewportTooSmall);
        }
        if (height + measured.height > layout.height + .001 &&
            fragments.isNotEmpty) {
          pauseWatch();
          yield BookPage(ordinal++, fragments);
          watch
            ..reset()
            ..start();
          check();
          fragments = [];
          height = 0;
          residentUnits = b.text.length;
          blocks = 1;
        }
        append(
          PageFragment(
            block: b,
            startUtf16: 0,
            endUtf16: b.text.length,
            clipTop: 0,
            textHeight: measured.height,
            fullTextHeight: measured.height,
            leading: 0,
            trailing: 0,
            atomic: true,
          ),
        );
      } else {
        var offset = 0;
        if (from != null &&
            from.ordinal >= b.ordinal &&
            from.ordinal <= sourceBlocks.last.ordinal) {
          for (final source in sourceBlocks) {
            if (source.ordinal < from.ordinal) offset += source.text.length;
            if (source.ordinal == from.ordinal) offset += from.offsetUtf16;
          }
        }
        if (!layout.validBoundary(text, offset)) {
          throw const PaginationFailure(PaginationError.invalidIndex);
        }
        for (var i = 0; i < measured.lines.length; i++) {
          check();
          final line = measured.lines[i];
          if (offset > line.start && offset < line.end) {
            throw const PaginationFailure(PaginationError.invalidIndex);
          }
          if (line.end <= offset && b.text.isNotEmpty) {
            continue;
          }
          final leading = line.start == 0 && slice.paragraphStart
                  ? 8.0 + measured.prefix
                  : 0.0,
              trailing = i == measured.lines.length - 1 && slice.paragraphEnd
                  ? 8.0
                  : 0.0;
          final parts = <PageFragment>[];
          var base = 0;
          for (final source in sourceBlocks) {
            final start = (line.start - base).clamp(0, source.text.length);
            final end = (line.end - base).clamp(0, source.text.length);
            if (start < end || text.isEmpty) {
              final primary = parts.isEmpty;
              parts.add(
                PageFragment(
                  block: source,
                  startUtf16: start,
                  endUtf16: end,
                  clipTop: primary ? line.top : 0,
                  textHeight: primary ? line.height : 0,
                  fullTextHeight: primary ? measured.height : 0,
                  leading: primary ? leading : 0,
                  trailing: primary ? trailing : 0,
                  paragraphStart: slice.paragraphStart && source == b,
                  context: context,
                  contextStart: line.start,
                  contextEnd: line.end,
                  coverageOnly: !primary,
                ),
              );
            }
            base += source.text.length;
          }
          final f = parts.first;
          if (f.height > layout.height + .001) {
            throw const PaginationFailure(PaginationError.viewportTooSmall);
          }
          if ((height + f.height > layout.height + .001 ||
                  fragments.length + parts.length > 64) &&
              fragments.isNotEmpty) {
            pauseWatch();
            yield BookPage(ordinal++, fragments);
            watch
              ..reset()
              ..start();
            check();
            fragments = [];
            height = 0;
            residentUnits = text.length;
            blocks = sourceBlocks.length;
          }
          for (final part in parts) {
            append(part);
          }
          if (watch.elapsedMicroseconds > 8000) {
            if (watch.elapsedMicroseconds > maximumBatchMicros) {
              maximumBatchMicros = watch.elapsedMicroseconds;
            }
            watch.stop();
            await Future<void>.delayed(Duration.zero);
            check();
            watch
              ..reset()
              ..start();
          }
        }
      }
      if (watch.elapsedMicroseconds > maximumBatchMicros) {
        maximumBatchMicros = watch.elapsedMicroseconds;
      }
      watch.stop();
      await Future<void>.delayed(Duration.zero);
      check();
      watch
        ..reset()
        ..start();
    }
    check();
    if (fragments.isNotEmpty) {
      yield BookPage(ordinal, fragments);
    }
  }
}
