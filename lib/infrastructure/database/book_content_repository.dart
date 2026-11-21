import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/book_reader.dart';
import '../../domain/reader_experience.dart';
import '../../domain/paragraph_index.dart';
import '../epub/image_policy.dart';
import '../epub/epub_limits.dart';
import '../epub/bounded_xml_job.dart';

import 'package:drift/drift.dart';

import '../../domain/books.dart';
import '../files/book_file_store.dart';
import '../files/private_file_store.dart' show ResourceLease;
import 'prototype_database.dart';

class BookContentRepository implements ParagraphNavigationSource {
  BookContentRepository(this.db, this.files);
  final PrototypeDatabase db;
  final BookFileStore files;
  Future<void> _ready(ContentKey key) async {
    if (key.kind != ContentKind.book) {
      throw const BookFailure(BookError.invalidContent);
    }
    final row = await db
        .customSelect(
          "SELECT projection_version FROM books WHERE book_id=? AND state='ready'",
          variables: [Variable(key.id)],
        )
        .get();
    if (row.length != 1 ||
        row.single.read<int>('projection_version') != key.version) {
      throw const BookFailure(BookError.invalidContent);
    }
  }

  @override
  Future<List<BookChapter>> chapters(ContentKey key) async {
    await _ready(key);
    return (await db
            .customSelect(
              'SELECT * FROM book_chapters WHERE book_id=? ORDER BY ordinal',
              variables: [Variable(key.id)],
            )
            .get())
        .map(
          (r) => BookChapter(
            key: key,
            id: r.read<String>('chapter_id'),
            ordinal: r.read<int>('ordinal'),
            title: r.read<String>('title'),
            resource: r.read<String>('resource_href'),
            firstBlockOrdinal: r.read<int>('first_block_ordinal'),
            blockCount: r.read<int>('block_count'),
            textUnits: r.read<int>('text_units'),
          ),
        )
        .toList();
  }

  BookBlock _block(ContentKey key, QueryRow r) {
    final raw = jsonDecode(r.read<String>('inline_json')) as List;
    final inline = raw.map((value) {
      final m = value as Map;
      final start = m['start'] as int, end = m['end'] as int;
      return BookInline(
        startUtf16: start,
        endUtf16: end,
        emphasis: m['emphasis'] as bool,
        strong: m['strong'] as bool,
        link: m['link'] == null
            ? null
            : BookLink(m['link'] as String, start, end),
      );
    }).toList();
    return BookBlock(
      key: key,
      chapterId: r.read<String>('chapter_id'),
      id: r.read<String>('block_id'),
      ordinal: r.read<int>('ordinal'),
      kind: BookBlockKind.values.byName(r.read<String>('kind')),
      text: r.read<String>('source_text'),
      speechEligible: r.read<int>('speech_eligible') == 1,
      resourceId: r.readNullable<String>('resource_id'),
      alternative: r.readNullable<String>('alternative'),
      inline: inline,
    );
  }

  @override
  Future<BookWindow> window(
    ContentKey key,
    int generation, {
    BookCursor? after,
    int maxBlocks = 64,
    int maxUnits = 65536,
  }) async {
    await _ready(key);
    after?.validate(key, generation);
    if (generation < 1 ||
        maxBlocks < 1 ||
        maxBlocks > 64 ||
        maxUnits < 1 ||
        maxUnits > 65536) {
      throw const BookFailure(BookError.limitExceeded);
    }
    final start = after?.nextOrdinal ?? 0;
    // Read one row at a time: no oversized prefetch hidden behind the window quota.
    final blocks = <BookBlock>[];
    var units = 0, next = start;
    while (blocks.length < maxBlocks) {
      final rows = await db
          .customSelect(
            'SELECT * FROM book_blocks WHERE book_id=? AND ordinal=?',
            variables: [Variable(key.id), Variable(next)],
          )
          .get();
      if (rows.isEmpty) break;
      final b = _block(key, rows.single);
      if (units + b.text.length > maxUnits) {
        if (blocks.isEmpty) throw const BookFailure(BookError.limitExceeded);
        break;
      }
      blocks.add(b);
      units += b.text.length;
      next++;
    }
    final exists = await db
        .customSelect(
          'SELECT ordinal FROM book_blocks WHERE book_id=? AND ordinal=?',
          variables: [Variable(key.id), Variable(next)],
        )
        .get();
    if (blocks.isEmpty && start > 0) {
      throw const BookFailure(BookError.invalidCursor);
    }
    return BookWindow(
      key: key,
      generation: generation,
      blocks: blocks,
      next: exists.isEmpty
          ? null
          : BookCursor(key: key, generation: generation, nextOrdinal: next),
    );
  }

  @override
  Future<BookLocator> resolveAnchor(
    ContentKey key,
    String resource,
    String fragment,
  ) async {
    await _ready(key);
    final rows = await db
        .customSelect(
          'SELECT * FROM book_anchors WHERE book_id=? AND resource_href=? AND fragment=?',
          variables: [Variable(key.id), Variable(resource), Variable(fragment)],
        )
        .get();
    if (rows.length != 1) throw const BookFailure(BookError.invalidLocator);
    final r = rows.single;
    final locator = BookLocator(
      key: key,
      chapterId: r.read<String>('chapter_id'),
      blockId: r.read<String>('block_id'),
      offsetUtf16: r.read<int>('offset_utf16'),
    );
    await validateLocator(locator);
    return locator;
  }

  @override
  Future<void> validateLocator(BookLocator locator) async {
    await _ready(locator.key);
    final rows = await db
        .customSelect(
          'SELECT * FROM book_blocks WHERE book_id=? AND block_id=?',
          variables: [Variable(locator.key.id), Variable(locator.blockId)],
        )
        .get();
    if (rows.length != 1) throw const BookFailure(BookError.invalidLocator);
    locator.validate(_block(locator.key, rows.single));
  }

  @override
  Future<BookBlock> block(ContentKey key, String blockId) async {
    await _ready(key);
    final rows = await db
        .customSelect(
          'SELECT * FROM book_blocks WHERE book_id=? AND block_id=?',
          variables: [Variable(key.id), Variable(blockId)],
        )
        .get();
    if (rows.length != 1) throw const BookFailure(BookError.invalidLocator);
    return _block(key, rows.single);
  }

  @override
  Future<BookWindow> windowAt(BookLocator locator, int generation) async {
    await validateLocator(locator);
    final b = await block(locator.key, locator.blockId);
    return window(
      locator.key,
      generation,
      after: BookCursor(
        key: locator.key,
        generation: generation,
        nextOrdinal: b.ordinal,
      ),
    );
  }

  @override
  Future<BookWindow> windowBefore(
    ContentKey key,
    int generation,
    int firstOrdinal,
  ) async {
    await _ready(key);
    if (firstOrdinal <= 0) throw const BookFailure(BookError.invalidCursor);
    final rows = await db
        .customSelect(
          'SELECT ordinal,text_units FROM book_blocks WHERE book_id=? AND ordinal<? ORDER BY ordinal DESC LIMIT 64',
          variables: [Variable(key.id), Variable(firstOrdinal)],
        )
        .get();
    if (rows.isEmpty || rows.first.read<int>('ordinal') != firstOrdinal - 1) {
      throw const BookFailure(BookError.invalidCursor);
    }
    var units = 0, start = firstOrdinal;
    for (final r in rows) {
      final n = r.read<int>('text_units');
      if (units + n > 65536) break;
      units += n;
      start = r.read<int>('ordinal');
    }
    // Bound forward loading to the previous range, not the current page.
    return window(
      key,
      generation,
      after: BookCursor(key: key, generation: generation, nextOrdinal: start),
      maxBlocks: firstOrdinal - start,
      maxUnits: 65536,
    );
  }

  @override
  Future<void> validateReadingBoundary(BookLocator locator) async {
    final b = await block(locator.key, locator.blockId);
    locator.validate(b);
    final index = ParagraphIndex();
    if (!index.validBoundary(b, locator.offsetUtf16)) {
      throw const BookFailure(BookError.invalidLocator);
    }
    final identity = index.identity(b), slice = index.slice(b);
    if (identity != b.id && locator.offsetUtf16 == 0 && slice > 0) {
      final previous = await block(locator.key, '$identity-s${slice - 1}');
      if (!index.validTextBoundary(
        previous.text + b.text,
        previous.text.length,
      )) {
        throw const BookFailure(BookError.invalidLocator);
      }
    }
    if (identity != b.id && locator.offsetUtf16 == b.text.length) {
      final rows = await db
          .customSelect(
            'SELECT source_text FROM book_blocks WHERE book_id=? AND block_id=?',
            variables: [
              Variable(locator.key.id),
              Variable('$identity-s${slice + 1}'),
            ],
          )
          .get();
      if (rows.isNotEmpty &&
          !index.validTextBoundary(
            b.text + rows.single.read<String>('source_text'),
            b.text.length,
          )) {
        throw const BookFailure(BookError.invalidLocator);
      }
    }
  }

  @override
  Future<ParagraphRange> paragraphAt(BookLocator locator) async {
    await validateReadingBoundary(locator);
    final current = await block(locator.key, locator.blockId);
    final index = ParagraphIndex(),
        identity = ParagraphIndex().identity(current);
    if (identity == current.id) return index.range(current, current);
    final first = await block(locator.key, '$identity-s0');
    final stem = '$identity-s';
    // Aggregate scalar metadata: never load all text of an arbitrarily long paragraph.
    final summary = await db
        .customSelect(
          'SELECT COUNT(*) AS n,MIN(ordinal) AS lo,MAX(ordinal) AS hi FROM book_blocks WHERE book_id=? AND substr(block_id,1,?)=?',
          variables: [
            Variable(locator.key.id),
            Variable(stem.length),
            Variable(stem),
          ],
        )
        .getSingle();
    final n = summary.read<int>('n'),
        lo = summary.read<int>('lo'),
        hi = summary.read<int>('hi');
    if (n < 1 || lo != first.ordinal || hi - lo + 1 != n) {
      throw const BookFailure(BookError.invalidContent);
    }
    final invalid = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM book_blocks WHERE book_id=? AND ordinal BETWEEN ? AND ? AND (block_id != ? || CAST(ordinal-? AS TEXT) OR chapter_id!=? OR kind!=? OR speech_eligible!=?)',
          variables: [
            Variable(locator.key.id),
            Variable(lo),
            Variable(hi),
            Variable(stem),
            Variable(lo),
            Variable(first.chapterId),
            Variable(first.kind.name),
            Variable(first.speechEligible ? 1 : 0),
          ],
        )
        .getSingle();
    if (invalid.read<int>('n') != 0) {
      throw const BookFailure(BookError.invalidContent);
    }
    final last = await block(locator.key, '$stem${n - 1}');
    final range = index.range(first, last);
    if (current.ordinal < lo || current.ordinal > hi) {
      throw const BookFailure(BookError.invalidLocator);
    }
    return range;
  }

  @override
  Future<ParagraphPage> paragraphs(
    ContentKey key,
    int generation, {
    BookCursor? after,
    int limit = 50,
  }) async {
    await _ready(key);
    after?.validate(key, generation);
    if (generation < 1 || limit < 1 || limit > 50) {
      throw const BookFailure(BookError.limitExceeded);
    }
    var next = after?.nextOrdinal ?? 0;
    final ranges = <ParagraphRange>[];
    while (ranges.length < limit) {
      final rows = await db
          .customSelect(
            'SELECT block_id,chapter_id FROM book_blocks WHERE book_id=? AND ordinal=?',
            variables: [Variable(key.id), Variable(next)],
          )
          .get();
      if (rows.isEmpty) {
        if (ranges.isEmpty && next > 0) {
          throw const BookFailure(BookError.invalidCursor);
        }
        return ParagraphPage(
          key: key,
          generation: generation,
          paragraphs: ranges,
        );
      }
      final row = rows.single;
      final range = await paragraphAt(
        BookLocator(
          key: key,
          chapterId: row.read<String>('chapter_id'),
          blockId: row.read<String>('block_id'),
          offsetUtf16: 0,
        ),
      );
      if (range.firstOrdinal != next) {
        throw const BookFailure(BookError.invalidCursor);
      }
      ranges.add(range);
      next = range.lastOrdinal + 1;
    }
    final more = await db
        .customSelect(
          'SELECT ordinal FROM book_blocks WHERE book_id=? AND ordinal=?',
          variables: [Variable(key.id), Variable(next)],
        )
        .get();
    return ParagraphPage(
      key: key,
      generation: generation,
      paragraphs: ranges,
      nextOrdinal: more.isEmpty ? null : next,
    );
  }

  @override
  Future<(int, int)> progress(BookLocator locator) async {
    await validateLocator(locator);
    final r = await db
        .customSelect(
          'SELECT units_before FROM book_blocks WHERE book_id=? AND block_id=?',
          variables: [Variable(locator.key.id), Variable(locator.blockId)],
        )
        .getSingle();
    final total = await db
        .customSelect(
          'SELECT COALESCE(SUM(text_units),0) AS n FROM book_chapters WHERE book_id=?',
          variables: [Variable(locator.key.id)],
        )
        .getSingle();
    return (
      r.read<int>('units_before') + locator.offsetUtf16,
      total.read<int>('n'),
    );
  }

  @override
  Future<BookImagePayload?> image(
    ContentKey key,
    String resourceId, {
    bool Function()? cancelled,
  }) async {
    await _ready(key);
    if (cancelled?.call() == true) return null;
    final rows = await db
        .customSelect(
          'SELECT * FROM book_resources WHERE book_id=? AND resource_id=?',
          variables: [Variable(key.id), Variable(resourceId)],
        )
        .get();
    if (rows.length != 1) return null;
    final r = rows.single;
    if (r.read<String>('state') != 'retained' ||
        r.read<String>('relative_path') != resourceId ||
        !['image/png', 'image/jpeg'].contains(r.read<String>('media_type'))) {
      return null;
    }
    try {
      final file = await files.bookFile(key.id, resourceId);
      final length = await file.length();
      if (length <= 0 ||
          length > EpubLimits.entryBytes ||
          length != r.read<int>('byte_size')) {
        return null;
      }
      final input = await file.open();
      late List<int> prefix;
      try {
        prefix = await input.read(length < 65536 ? length : 65536);
      } finally {
        await input.close();
      }
      final info = ImagePolicy.inspect(prefix);
      if (!info.usable ||
          info.width != r.readNullable<int>('width') ||
          info.height != r.readNullable<int>('height')) {
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      var sum = 0;
      await for (final chunk in file.openRead()) {
        if (cancelled?.call() == true) return null;
        sum += chunk.length;
        if (sum > length) return null;
        bytes.add(chunk);
      }
      if (sum != length) return null;
      final data = bytes.takeBytes();
      // Bounded chunks avoid a single large synchronous hash on the UI isolate.
      if (!await BoundedXmlJob.run(
            (data, r.read<String>('sha256')),
            _imageHashMatches,
            cancelled: cancelled,
          ) ||
          cancelled?.call() == true) {
        return null;
      }
      return BookImagePayload(data, info.width!, info.height!);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ContentLease> acquire(ContentKey key) async {
    await _ready(key);
    final lease = await files.acquire(key.id);
    try {
      await _ready(key);
      return _Lease(lease);
    } catch (_) {
      lease.release();
      rethrow;
    }
  }
}

class _Lease implements ContentLease {
  _Lease(this.lease);
  final ResourceLease lease;
  @override
  Future<void> release() async {
    lease.release();
  }
}

Future<bool> _imageHashMatches((Uint8List, String) value) async =>
    sha256.convert(value.$1).toString() == value.$2;
