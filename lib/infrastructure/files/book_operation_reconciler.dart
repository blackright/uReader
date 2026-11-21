import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../domain/books.dart';
import '../database/book_repository.dart';
import '../database/book_operation_repository.dart';
import 'book_file_store.dart';

/// Never discovers books from directories. Only recorded, validated jobs publish.
class BookOperationReconciler {
  BookOperationReconciler(
    this.books,
    this.journal,
    this.files, {
    this.purgeAudio,
  });
  final BookRepository books;
  final BookOperationRepository journal;
  final BookFileStore files;
  final Future<void> Function(ContentKey)? purgeAudio;
  Future<void> finishDeletion(BookOperation op) async {
    final key = await journal.deletionKey(op);
    if (key == null) return;
    if (purgeAudio == null) {
      throw const BookFailure(BookError.operationInProgress);
    }
    await files.waitForRelease(key.id);
    await purgeAudio!(key);
    while (true) {
      final imports = await journal.retiredImports(key.id);
      if (imports.isEmpty) break;
      for (final id in imports) {
        await files.removeStaging(id);
        await journal.forgetRetiredImport(key.id, id);
      }
    }
    await files.removeBook(key.id);
    await journal.finishDeletion(op);
  }

  Future<List<BookFailure>> recover({int limit = 64}) async {
    final issues = <BookFailure>[];
    final pending = await journal.pending(limit: limit);
    for (final op in pending.where(
      (op) => op.kind == BookOperationKind.delete,
    )) {
      try {
        await finishDeletion(op);
      } catch (_) {
        await journal.failDeletion(op);
        issues.add(const BookFailure(BookError.storageUnavailable));
      }
    }
    for (final op in pending) {
      if (op.kind != BookOperationKind.import) continue;
      if (await journal.deletion(op.bookId) != null) continue;
      if (op.phase == BookOperationPhase.validated) {
        if (!await journal.canPublish(op)) continue;
        try {
          await publish(op);
        } on BookFailure catch (e) {
          if (![
            BookError.invalidContent,
            BookError.invalidArchive,
            BookError.limitExceeded,
          ].contains(e.code)) {
            rethrow;
          }
          await journal.fail(op, e.code);
          issues.add(e);
          await _cleanup(op);
        }
      } else if ([
        BookOperationPhase.copying,
        BookOperationPhase.validating,
        BookOperationPhase.error,
      ].contains(op.phase)) {
        await _cleanup(op);
      }
    }
    return issues;
  }

  Future<void> _cleanup(BookOperation op) async {
    if (!await journal.claimCleanup(op)) return;
    await files.removeStaging(op.id);
    await files.removeBook(op.bookId);
    await journal.finishCleanup(op);
  }

  Future<void> publish(BookOperation op) async {
    final proof = await journal.proof(op.id, op.bookId);
    final expected = proof['manifest_sha256'] as String;
    final staged = await files.stagingFile(op.id, 'manifest');
    final published = await files.bookFile(op.bookId, 'manifest');
    final stagedExists = await staged.exists(),
        publishedExists = await published.exists();
    if (stagedExists == publishedExists) {
      throw const BookFailure(BookError.invalidContent);
    }
    final manifestFile = stagedExists ? staged : published;
    if (await manifestFile.length() > 2097152) {
      throw const BookFailure(BookError.limitExceeded);
    }
    final bytes = await manifestFile.readAsBytes();
    if (sha256.convert(bytes).toString() != expected ||
        utf8.decode(bytes) != proof['validation_json']) {
      throw const BookFailure(BookError.invalidContent);
    }
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map ||
        raw['version'] != 1 ||
        raw['operation'] != op.id ||
        raw['book'] != op.bookId ||
        raw['sourceSha'] != proof['source_sha256'] ||
        raw['canonicalSha'] != await journal.canonicalDigest(op.bookId) ||
        raw['files'] is! List) {
      throw const BookFailure(BookError.invalidContent);
    }
    final rows = raw['files'] as List;
    if (rows.length > 5001) throw const BookFailure(BookError.limitExceeded);
    final seen = <String>{};
    for (final row in rows) {
      if (row is! Map ||
          row['id'] is! String ||
          row['sha'] is! String ||
          row['bytes'] is! int ||
          !seen.add(row['id'] as String)) {
        throw const BookFailure(BookError.invalidContent);
      }
      final id = row['id'] as String;
      final File file = stagedExists
          ? await files.stagingFile(op.id, id)
          : await files.bookFile(op.bookId, id);
      if (await file.length() != row['bytes'] ||
          (await sha256.bind(file.openRead()).first).toString() != row['sha']) {
        throw const BookFailure(BookError.invalidContent);
      }
    }
    if (!seen.contains('source')) {
      throw const BookFailure(BookError.invalidContent);
    }
    final source = rows.singleWhere((r) => r['id'] == 'source') as Map;
    if (source['sha'] != raw['sourceSha']) {
      throw const BookFailure(BookError.invalidContent);
    }
    if (stagedExists) await files.publish(op.id, op.bookId);
    await books.commitReady(op.id, op.bookId, expected);
  }
}
