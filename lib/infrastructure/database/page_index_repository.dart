import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../domain/books.dart';
import '../../domain/pagination.dart';
import 'prototype_database.dart';

/// Cache ownership is an opaque id:nonce handle, distinct from layout generations.
class PageIndexRepository implements PageIndexStore {
  PageIndexRepository(this.db);
  final PrototypeDatabase db;
  @override
  Future<String> sourceDigest(ContentKey key) async {
    final row = await db
        .customSelect(
          "SELECT source_sha256,manifest_sha256 FROM books WHERE book_id=? AND projection_version=? AND state='ready'",
          variables: [Variable(key.id), Variable(key.version)],
        )
        .getSingleOrNull();
    if (key.kind != ContentKind.book || row == null) {
      throw const BookFailure(BookError.invalidContent);
    }
    return LayoutFingerprint.of({
      'source': row.read<String>('source_sha256'),
      'projection': row.read<String>('manifest_sha256'),
    }).value;
  }

  String _nonce() => List.generate(
    4,
    (_) =>
        Random.secure().nextInt(0x100000000).toRadixString(16).padLeft(8, '0'),
  ).join();
  (String, String) _handle(String handle) {
    final parts = handle.split(':');
    if (parts.length != 2 ||
        !RegExp(r'^page-[a-f0-9]{32}$').hasMatch(parts[0]) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(parts[1])) {
      throw const PaginationFailure(PaginationError.stale);
    }
    return (parts[0], parts[1]);
  }

  @override
  Future<String> begin(
    ContentKey key,
    String fingerprint,
    int generation,
  ) async {
    LayoutFingerprint(fingerprint);
    if (key.kind != ContentKind.book || generation < 1) {
      throw const PaginationFailure(PaginationError.invalidIndex);
    }
    return db.transaction(() async {
      final ready = await db
          .customSelect(
            "SELECT book_id FROM books WHERE book_id=? AND projection_version=? AND state='ready'",
            variables: [Variable(key.id), Variable(key.version)],
          )
          .get();
      if (ready.length != 1) {
        throw const BookFailure(BookError.invalidContent);
      }
      var rows = await db
          .customSelect(
            'SELECT * FROM book_page_runs WHERE book_id=? AND projection_version=? AND fingerprint=?',
            variables: [
              Variable(key.id),
              Variable(key.version),
              Variable(fingerprint),
            ],
          )
          .get();
      // Reject/delete corrupt derived caches only; never delete bookmarks or source data.
      if (rows.isNotEmpty && !await _valid(rows.single)) {
        await db.customStatement('DELETE FROM book_page_runs WHERE run_id=?', [
          rows.single.read<String>('run_id'),
        ]);
        rows = [];
      }
      final owner = _nonce();
      final now = DateTime.now().microsecondsSinceEpoch;
      final id = rows.isEmpty
          ? 'page-${_nonce()}'
          : rows.single.read<String>('run_id');
      if (rows.isEmpty) {
        await db.customStatement(
          "INSERT INTO book_page_runs VALUES (?,?,?,?,'calculating',?,0,?,NULL,?)",
          [
            id,
            key.id,
            key.version,
            fingerprint,
            generation,
            jsonEncode({'owner': owner}),
            now,
          ],
        );
      } else {
        final checkpoint = jsonDecode(
          rows.single.read<String>('checkpoint_json'),
        ) as Map<String, dynamic>;
        checkpoint['owner'] = owner;
        await db.customStatement(
          'UPDATE book_page_runs SET generation=?,checkpoint_json=?,last_access_at=? WHERE run_id=?',
          [generation, jsonEncode(checkpoint), now, id],
        );
      }
      final old = await db
          .customSelect(
            'SELECT run_id FROM book_page_runs WHERE book_id=? ORDER BY last_access_at DESC,run_id DESC LIMIT -1 OFFSET 2',
            variables: [Variable(key.id)],
          )
          .get();
      for (final row in old) {
        await db.customStatement('DELETE FROM book_page_runs WHERE run_id=?', [
          row.read<String>('run_id'),
        ]);
      }
      return '$id:$owner';
    });
  }

  Future<bool> _valid(QueryRow row) async {
    try {
      final checkpoint = jsonDecode(row.read<String>('checkpoint_json')) as Map;
      if (checkpoint['owner'] is! String ||
          !RegExp(r'^[a-f0-9]{32}$').hasMatch(checkpoint['owner'] as String)) {
        return false;
      }
      final id = row.read<String>('run_id'),
          prefix = row.read<int>('prefix_pages');
      final stats = await db
          .customSelect(
            'SELECT COUNT(*) AS n, MIN(page_ordinal) AS lo, MAX(page_ordinal) AS hi FROM book_page_boundaries WHERE run_id=?',
            variables: [Variable(id)],
          )
          .getSingle();
      if (stats.read<int>('n') != prefix ||
          (prefix > 0 &&
              (stats.read<int>('lo') != 0 ||
                  stats.read<int>('hi') != prefix - 1))) {
        return false;
      }
      final invalid = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM book_page_boundaries b LEFT JOIN book_page_boundaries p ON p.run_id=b.run_id AND p.page_ordinal=b.page_ordinal-1 WHERE b.run_id=? AND (b.start_utf16>8192 OR b.end_utf16>8192 OR (b.page_ordinal=0 AND (b.start_ordinal!=0 OR b.start_utf16!=0)) OR (b.page_ordinal>0 AND (b.start_ordinal!=p.end_ordinal OR b.start_utf16!=p.end_utf16)))',
            variables: [Variable(id)],
          )
          .getSingle();
      if (invalid.read<int>('n') != 0) return false;
      if (row.read<String>('state') == 'ready') {
        final end = await db
            .customSelect(
              'SELECT COALESCE(MAX(ordinal)+1,0) AS n FROM book_blocks WHERE book_id=?',
              variables: [Variable(row.read<String>('book_id'))],
            )
            .getSingle();
        if (prefix == 0
            ? end.read<int>('n') != 0
            : checkpoint['ordinal'] != end.read<int>('n') ||
                  checkpoint['offset'] != 0) {
          return false;
        }
      }
      if (prefix == 0) {
        return checkpoint['ordinal'] == null && checkpoint['offset'] == null;
      }
      final last = await db
          .customSelect(
            'SELECT end_ordinal,end_utf16 FROM book_page_boundaries WHERE run_id=? AND page_ordinal=?',
            variables: [Variable(id), Variable(prefix - 1)],
          )
          .getSingle();
      return checkpoint['ordinal'] == last.read<int>('end_ordinal') &&
          checkpoint['offset'] == last.read<int>('end_utf16');
    } catch (_) {
      return false;
    }
  }

  Future<QueryRow?> _owned(String handle) async {
    final parts = _handle(handle);
    final rows = await db
        .customSelect(
          "SELECT r.* FROM book_page_runs r JOIN books b ON b.book_id=r.book_id AND b.projection_version=r.projection_version WHERE r.run_id=? AND b.state='ready'",
          variables: [Variable(parts.$1)],
        )
        .get();
    if (rows.isEmpty) return null;
    try {
      if ((jsonDecode(rows.single.read<String>('checkpoint_json'))
              as Map)['owner'] !=
          parts.$2) {
        return null;
      }
    } catch (_) {
      return null;
    }
    return rows.single;
  }

  @override
  Future<PaginationRun?> read(String handle) async {
    final row = await _owned(handle);
    if (row == null) return null;
    if (!await _valid(row)) {
      await db.customStatement(
        'DELETE FROM book_page_runs WHERE run_id=? AND generation=? AND checkpoint_json=?',
        [
          row.read<String>('run_id'),
          row.read<int>('generation'),
          row.read<String>('checkpoint_json'),
        ],
      );
      return null;
    }
    final data = jsonDecode(row.read<String>('checkpoint_json')) as Map;
    return PaginationRun(
      id: handle,
      key: ContentKey(
        ContentKind.book,
        row.read<String>('book_id'),
        row.read<int>('projection_version'),
      ),
      fingerprint: LayoutFingerprint(row.read<String>('fingerprint')),
      generation: row.read<int>('generation'),
      prefixPages: row.read<int>('prefix_pages'),
      state: row.read<String>('state'),
      total: row.readNullable<int>('total'),
      checkpoint: data['ordinal'] == null
          ? null
          : PagePoint(data['ordinal'] as int, data['offset'] as int),
    );
  }

  Future<bool> _pointValid(
    ContentKey key,
    PagePoint point, {
    bool end = false,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT source_text FROM book_blocks WHERE book_id=? AND ordinal=?',
          variables: [Variable(key.id), Variable(point.ordinal)],
        )
        .get();
    if (rows.isNotEmpty) {
      return validUtf16Offset(
        rows.single.read<String>('source_text'),
        point.offsetUtf16,
      );
    }
    if (!end || point.offsetUtf16 != 0) return false;
    final last = await db
        .customSelect(
          'SELECT COALESCE(MAX(ordinal)+1,0) AS n FROM book_blocks WHERE book_id=?',
          variables: [Variable(key.id)],
        )
        .getSingle();
    return point.ordinal == last.read<int>('n');
  }

  @override
  Future<void> append(
    String handle,
    List<PageBoundary> pages, {
    required int generation,
    required bool complete,
  }) async {
    if (pages.length > 128) {
      throw const PaginationFailure(PaginationError.invalidIndex);
    }
    await db.transaction(() async {
      final run = await read(handle);
      if (run == null ||
          run.generation != generation ||
          run.state != 'calculating') {
        throw const PaginationFailure(PaginationError.stale);
      }
      var count = run.prefixPages, at = run.checkpoint ?? PagePoint(0, 0);
      for (final page in pages) {
        if (!await _pointValid(run.key, page.start) ||
            !await _pointValid(run.key, page.end, end: true)) {
          throw const PaginationFailure(PaginationError.invalidIndex);
        }
        if (page.ordinal != count || page.start != at) {
          throw const PaginationFailure(PaginationError.invalidIndex);
        }
        await db.customStatement(
          'INSERT INTO book_page_boundaries VALUES (?,?,?,?,?,?)',
          [
            _handle(handle).$1,
            page.ordinal,
            page.start.ordinal,
            page.start.offsetUtf16,
            page.end.ordinal,
            page.end.offsetUtf16,
          ],
        );
        count++;
        at = page.end;
      }
      if (complete) {
        final last = await db
            .customSelect(
              'SELECT COALESCE(MAX(ordinal)+1,0) AS n FROM book_blocks WHERE book_id=?',
              variables: [Variable(run.key.id)],
            )
            .getSingle();
        if (at != PagePoint(last.read<int>('n'), 0)) {
          throw const PaginationFailure(PaginationError.invalidIndex);
        }
      }
      final checkpoint = <String, Object?>{
        'owner': _handle(handle).$2,
        if (count > 0) ...{'ordinal': at.ordinal, 'offset': at.offsetUtf16},
      };
      await db.customStatement(
        'UPDATE book_page_runs SET prefix_pages=?,checkpoint_json=?,state=?,total=?,last_access_at=? WHERE run_id=? AND generation=?',
        [
          count,
          jsonEncode(checkpoint),
          complete ? 'ready' : 'calculating',
          complete ? count : null,
          DateTime.now().microsecondsSinceEpoch,
          _handle(handle).$1,
          generation,
        ],
      );
    });
  }

  @override
  Future<List<PageBoundary>> boundaries(
    String handle,
    int first, {
    int limit = 128,
  }) async {
    if (first < 0 || limit < 1 || limit > 128) {
      throw const PaginationFailure(PaginationError.invalidIndex);
    }
    final run = await read(handle);
    if (run == null) {
      throw const PaginationFailure(PaginationError.stale);
    }
    final rows = await db
        .customSelect(
          'SELECT * FROM book_page_boundaries WHERE run_id=? AND page_ordinal>=? ORDER BY page_ordinal LIMIT ?',
          variables: [
            Variable(_handle(handle).$1),
            Variable(first),
            Variable(limit),
          ],
        )
        .get();
    return [
      for (final row in rows)
        PageBoundary(
          ordinal: row.read<int>('page_ordinal'),
          start: PagePoint(
            row.read<int>('start_ordinal'),
            row.read<int>('start_utf16'),
          ),
          end: PagePoint(
            row.read<int>('end_ordinal'),
            row.read<int>('end_utf16'),
          ),
        ),
    ];
  }

  @override
  Future<void> invalidate(String handle) async {
    await db.transaction(() async {
      if (await _owned(handle) != null) {
        await db.customStatement('DELETE FROM book_page_runs WHERE run_id=?', [
          _handle(handle).$1,
        ]);
      }
    });
  }
}
