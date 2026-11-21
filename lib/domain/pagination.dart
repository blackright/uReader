import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'books.dart';

abstract interface class PageIndexStore {
  Future<String> sourceDigest(ContentKey key);
  Future<String> begin(ContentKey key, String fingerprint, int generation);
  Future<PaginationRun?> read(String handle);
  Future<void> append(
    String handle,
    List<PageBoundary> pages, {
    required int generation,
    required bool complete,
  });
  Future<List<PageBoundary>> boundaries(
    String handle,
    int first, {
    int limit = 128,
  });
  Future<void> invalidate(String handle);
}

enum PaginationError {
  viewportTooSmall,
  cancelled,
  invalidIndex,
  stale,
  unsafeSliceBoundary,
}

class PaginationFailure implements Exception {
  const PaginationFailure(this.code);
  final PaginationError code;
}

class LayoutFingerprint {
  LayoutFingerprint(this.value) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw const PaginationFailure(PaginationError.invalidIndex);
    }
  }
  factory LayoutFingerprint.of(Map<String, Object?> values) =>
      LayoutFingerprint(
        sha256
            .convert(
              utf8.encode(
                jsonEncode(SplayTreeMap<String, Object?>.from(values)),
              ),
            )
            .toString(),
      );
  final String value;
  @override
  bool operator ==(Object other) =>
      other is LayoutFingerprint && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

class PagePoint implements Comparable<PagePoint> {
  PagePoint(this.ordinal, this.offsetUtf16) {
    if (ordinal < 0 || offsetUtf16 < 0 || offsetUtf16 > 8192) {
      throw const PaginationFailure(PaginationError.invalidIndex);
    }
  }
  final int ordinal, offsetUtf16;
  @override
  int compareTo(PagePoint other) => ordinal == other.ordinal
      ? offsetUtf16.compareTo(other.offsetUtf16)
      : ordinal.compareTo(other.ordinal);
  @override
  bool operator ==(Object other) =>
      other is PagePoint &&
      ordinal == other.ordinal &&
      offsetUtf16 == other.offsetUtf16;
  @override
  int get hashCode => Object.hash(ordinal, offsetUtf16);
}

class PageBoundary {
  PageBoundary({
    required this.ordinal,
    required this.start,
    required this.end,
  }) {
    if (ordinal < 0 || start.compareTo(end) >= 0) {
      throw const PaginationFailure(PaginationError.invalidIndex);
    }
  }
  final int ordinal;
  final PagePoint start, end;
}

/// Transient shaping context only; canonical blocks and their locators stay intact.
/// At most two source slices (16,384 UTF16 units), never a whole chapter.
class PageTextContext {
  PageTextContext(List<BookBlock> source) : blocks = List.unmodifiable(source) {
    if (source.length != 2 ||
        source[0].key != source[1].key ||
        source[1].ordinal != source[0].ordinal + 1 ||
        source[0].kind != source[1].kind ||
        source.any((b) => b.text.isEmpty)) {
      throw const PaginationFailure(PaginationError.invalidIndex);
    }
  }
  final List<BookBlock> blocks;
  late final String text = blocks.map((b) => b.text).join();
}

class PageFragment {
  PageFragment({
    required this.block,
    required this.startUtf16,
    required this.endUtf16,
    required this.clipTop,
    required this.textHeight,
    required this.fullTextHeight,
    required this.leading,
    required this.trailing,
    this.atomic = false,
    this.paragraphStart = true,
    this.context,
    this.contextStart = 0,
    this.contextEnd = 0,
    this.coverageOnly = false,
  }) {
    if (context != null &&
            (!context!.blocks.contains(block) ||
                contextStart < 0 ||
                contextEnd > context!.text.length ||
                contextStart >= contextEnd) ||
        coverageOnly &&
            (context == null ||
                textHeight != 0 ||
                leading != 0 ||
                trailing != 0) ||
        !validUtf16Offset(block.text, startUtf16) ||
        !validUtf16Offset(block.text, endUtf16) ||
        startUtf16 > endUtf16 ||
        [
          clipTop,
          textHeight,
          fullTextHeight,
          leading,
          trailing,
        ].any((n) => !n.isFinite || n < 0)) {
      throw const PaginationFailure(PaginationError.invalidIndex);
    }
  }
  final PageTextContext? context;
  final int contextStart, contextEnd;
  final bool coverageOnly;
  final BookBlock block;
  final int startUtf16, endUtf16;
  final double clipTop, textHeight, fullTextHeight, leading, trailing;
  final bool atomic, paragraphStart;
  double get height => leading + textHeight + trailing;
  bool get first => startUtf16 == 0;
  bool get startsParagraph => paragraphStart && first;
  bool get last => endUtf16 == block.text.length;
  String get identity => '${block.id}:$startUtf16:$endUtf16';
  PagePoint get start => PagePoint(block.ordinal, startUtf16);
  PagePoint get end => last
      ? PagePoint(block.ordinal + 1, 0)
      : PagePoint(block.ordinal, endUtf16);
  BookLocator get locator => BookLocator(
    key: block.key,
    chapterId: block.chapterId,
    blockId: block.id,
    offsetUtf16: startUtf16,
  );
}

class BookPage {
  BookPage(this.ordinal, List<PageFragment> fragments)
    : fragments = List.unmodifiable(fragments) {
    if (ordinal < 0 ||
        fragments.isEmpty ||
        fragments.length > 64 ||
        fragments.any((f) => f.block.key != fragments.first.block.key)) {
      throw const PaginationFailure(PaginationError.invalidIndex);
    }
  }
  final int ordinal;
  final List<PageFragment> fragments;
  double get height => fragments.fold(0, (n, f) => n + f.height);
  PagePoint get start => fragments.first.start;
  PagePoint get end => fragments.last.end;
  PageBoundary get boundary =>
      PageBoundary(ordinal: ordinal, start: start, end: end);
}

class PaginationRun {
  PaginationRun({
    required this.id,
    required this.key,
    required this.fingerprint,
    required this.generation,
    required this.prefixPages,
    required this.state,
    this.total,
    this.checkpoint,
  }) {
    if (id.isEmpty ||
        generation < 1 ||
        prefixPages < 0 ||
        !const ['calculating', 'ready', 'cancelled', 'error'].contains(state) ||
        (state == 'ready' ? (total != prefixPages) : (total != null))) {
      throw const PaginationFailure(PaginationError.invalidIndex);
    }
  }
  final String id, state;
  final ContentKey key;
  final LayoutFingerprint fingerprint;
  final int generation, prefixPages;
  final int? total;
  final PagePoint? checkpoint;
}
