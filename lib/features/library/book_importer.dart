import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/books.dart';
import '../../infrastructure/database/book_repository.dart';
import '../../infrastructure/database/book_operation_repository.dart';
import '../../infrastructure/files/book_file_store.dart';
import '../../infrastructure/files/book_operation_reconciler.dart';
import '../../infrastructure/epub/epub_import_source.dart';
import '../../infrastructure/epub/epub_package_parser.dart';
import '../../infrastructure/epub/epub_projection_worker.dart';
import '../../infrastructure/epub/xhtml_projector.dart';
import '../../infrastructure/epub/epub_limits.dart';
import '../../infrastructure/epub/image_policy.dart';
import '../../infrastructure/epub/bounded_xml_job.dart';

enum ImportStep {
  choosing,
  copying,
  validating,
  finalizing,
  complete,
  cancelled,
  failed,
}

class ImportProgress {
  const ImportProgress(this.step, {this.bytes = 0});
  final ImportStep step;
  final int bytes;
  bool get canCancel => ![
    ImportStep.finalizing,
    ImportStep.complete,
    ImportStep.cancelled,
    ImportStep.failed,
  ].contains(step);
}

class BookImportResult {
  const BookImportResult({
    this.book,
    this.existing = false,
    this.cancelled = false,
  });
  final Book? book;
  final bool existing, cancelled;
}

/// One active operation, explicit final commit and awaited shutdown boundaries.
class BookImporter {
  BookImporter({
    required this.source,
    required this.books,
    required this.files,
    required this.normalizeKey,
  }) : journal = BookOperationRepository(books.db);
  final EpubImportSource source;
  final BookRepository books;
  final BookFileStore files;
  final BookOperationRepository journal;
  final Future<String> Function(String) normalizeKey;
  bool _busy = false,
      _cancelled = false,
      _finalizing = false,
      _selected = false;
  bool _shuttingDown = false;
  Completer<void>? _settled;
  String? _operation;
  int _generation = 0;
  void _check() {
    if (_cancelled) throw const BookFailure(BookError.cancelled);
  }

  Future<bool> cancel() async {
    if (!_busy || _finalizing) return false;
    _cancelled = true;
    if (_selected) await source.cancel(_operation!, _generation);
    return true;
  }

  Future<void> shutdown() async {
    _shuttingDown = true;
    final pending = _settled?.future;
    try {
      await cancel();
    } on BookFailure {
      /* The active operation still owns cleanup. */
    }
    if (pending != null) await pending;
  }

  Future<BookImportResult> importBook(
    String operation,
    String book,
    int generation, {
    void Function(ImportProgress)? progress,
  }) async {
    if (_shuttingDown) throw const BookFailure(BookError.storageUnavailable);
    if (_busy) throw const BookFailure(BookError.operationInProgress);
    _settled = Completer<void>();
    _busy = true;
    _cancelled = false;
    _finalizing = false;
    _selected = false;
    _operation = operation;
    _generation = generation;
    VerifiedEpubArchive? archive;
    var began = false;
    final progressClock = Stopwatch()..start();
    ImportStep? lastStep;
    int lastBytes = 0, lastMs = 0;
    void update(ImportStep step, {int bytes = 0}) {
      if (step == lastStep &&
          step == ImportStep.copying &&
          progressClock.elapsedMilliseconds - lastMs < 100 &&
          bytes - lastBytes < 1048576) {
        return;
      }
      lastStep = step;
      lastBytes = bytes;
      lastMs = progressClock.elapsedMilliseconds;
      progress?.call(ImportProgress(step, bytes: bytes));
    }

    try {
      await BookOperationReconciler(books, journal, files).recover();
      _check();
      await books.begin(operation, book, generation);
      began = true;
      _check();
      update(ImportStep.choosing);
      _selected = true;
      final handle = await source.choose(operation, generation);
      _check();
      if (handle == null) {
        _cancelled = true;
        throw const BookFailure(BookError.cancelled);
      }
      update(ImportStep.copying);
      final copied = await source.copyAndHash(
        handle,
        progress: (n) => update(ImportStep.copying, bytes: n),
      );
      _check();
      final existing = await books.reserve(
        operation,
        book,
        copied.sha256,
        copied.bytes,
      );
      if (existing != null) {
        await source.cancel(operation, generation);
        await files.removeStaging(operation);
        await books.abandon(operation, book);
        return BookImportResult(book: existing, existing: true);
      }
      update(ImportStep.validating, bytes: copied.bytes);
      archive = await source.openArchive();
      final clock = Stopwatch()..start();
      void checkAnalysis() {
        _check();
        if (clock.elapsed > EpubLimits.analysisDeadline) {
          throw const BookFailure(BookError.deadlineExceeded);
        }
      }

      final package = await EpubPackageParser(
        archive,
        fallbackTitle: source.displayName,
        cancelled: () => _cancelled,
      ).parse();
      final titleKey = await normalizeKey(package.title),
          authorKey = await normalizeKey(package.authors.join(' '));
      await books.metadata(
        operation,
        book,
        package,
        titleKey: titleKey,
        authorKey: authorKey,
      );
      final key = ContentKey(ContentKind.book, book, 1),
          projector = XhtmlProjector(
            ContentKey(ContentKind.book, book, 1),
            cancelled: () => _cancelled,
            initialElements: package.metadataElements,
          );
      var ordinal = 0, unitsBefore = 0;
      final evidence = <Map<String, Object>>[
        {'id': 'source', 'sha': copied.sha256, 'bytes': copied.bytes},
      ];
      final resourceByHref = <String, String>{}, styles = <String, String>{};
      Future<String?> retainImage(
        VerifiedEpubArchive input,
        String href,
      ) async {
        if (resourceByHref.containsKey(href)) return resourceByHref[href];
        final declared = package.items.where((i) => i.href == href).firstOrNull;
        if (declared == null ||
            !['image/png', 'image/jpeg'].contains(declared.mediaType) ||
            !input.names.contains(href)) {
          return null;
        }
        final data = await input.read(href, maxBytes: EpubLimits.entryBytes);
        checkAnalysis();
        final analysed = await BoundedXmlJob.run(
          data,
          _imageInfo,
          cancelled: () => _cancelled,
        );
        final inspection = analysed.inspection;
        final rid = 'r${resourceByHref.length}';
        resourceByHref[href] = rid;
        final sha = analysed.sha;
        if (inspection.usable) {
          await files.writeStaged(
            operation,
            rid,
            _chunks(data),
            maxBytes: data.length,
            cancelled: () => _cancelled,
          );
          evidence.add({'id': rid, 'sha': sha, 'bytes': data.length});
        }

        await books.resource(
          operation,
          book,
          id: rid,
          href: href,
          mediaType: inspection.format == 'png'
              ? 'image/png'
              : inspection.format == 'jpeg'
              ? 'image/jpeg'
              : 'application/octet-stream',
          bytes: data.length,
          sha: sha,
          width: inspection.width,
          height: inspection.height,
          retained: inspection.usable,
        );
        return rid;
      }

      if (package.cover != null) {
        final cover = await retainImage(archive, package.cover!);
        await books.setCover(operation, book, cover);
      }
      for (
        var chapterIndex = 0;
        chapterIndex < package.spine.length;
        chapterIndex++
      ) {
        checkAnalysis();
        final item = package.spine[chapterIndex];
        final xhtml = utf8.decode(
          await archive.read(item.href, maxBytes: EpubLimits.entryBytes),
        );
        final css = <String>[];
        for (final link in await EpubProjectionWorker.linkedStyles(
          xhtml,
          cancelled: () => _cancelled,
        )) {
          final uri = Uri.tryParse(link);
          if (uri == null || uri.hasScheme || uri.hasAuthority) continue;
          final href = resolveEpubReference(item.href, link);
          if (!package.items.any(
            (i) => i.href == href && i.mediaType == 'text/css',
          )) {
            continue;
          }
          if (!styles.containsKey(href)) {
            final bytes = await archive.read(
              href,
              maxBytes: EpubLimits.cssSheetBytes,
            );
            if (styles.values.fold<int>(
                      0,
                      (n, css) => n + utf8.encode(css).length,
                    ) +
                    bytes.length >
                EpubLimits.cssTotalBytes) {
              throw const BookFailure(BookError.limitExceeded);
            }
            styles[href] = utf8.decode(bytes);
          }
          css.add(styles[href]!);
        }
        final projected = await projector.project(
          chapterIndex,
          xhtml,
          styles: css,
        );
        for (final image in projected.imageSources.entries) {
          await retainImage(
            archive,
            resolveEpubReference(item.href, image.value),
          );
        }
        final blocks = projected.blocks
            .map(
              (b) => BookBlock(
                key: key,
                chapterId: b.chapterId,
                id: b.id,
                ordinal: b.ordinal,
                kind: b.kind,
                text: b.text,
                speechEligible: b.speechEligible,
                inline: b.inline,
                resourceId: b.resourceId == null
                    ? null
                    : resourceByHref[resolveEpubReference(
                        item.href,
                        projected.imageSources[b.resourceId]!,
                      )],
                alternative: b.alternative,
              ),
            )
            .toList();
        final chapterUnits = blocks.fold<int>(0, (n, b) => n + b.text.length);
        await books.chapter(
          operation,
          BookChapter(
            key: key,
            id: 'c$chapterIndex',
            ordinal: chapterIndex,
            title:
                package.chapterTitles[item.href] ??
                'Chapitre ${chapterIndex + 1}',
            resource: item.href,
            firstBlockOrdinal: ordinal,
            blockCount: blocks.length,
            textUnits: chapterUnits,
          ),
        );
        var batch = <BookBlock>[], batchUnits = 0;
        Future<void> flush() async {
          if (batch.isEmpty) return;
          await books.blocks(
            operation,
            batch,
            firstOrdinal: ordinal,
            unitsBefore: unitsBefore,
          );
          ordinal += batch.length;
          unitsBefore += batchUnits;
          batch = [];
          batchUnits = 0;
        }

        for (final block in blocks) {
          if (batch.length == 64 || batchUnits + block.text.length > 65536) {
            await flush();
          }
          batch.add(block);
          batchUnits += block.text.length;
        }
        await flush();
        await books.anchors(operation, item.href, projected.anchors);
      }
      if (unitsBefore == 0) throw const BookFailure(BookError.invalidContent);
      checkAnalysis();
      await archive.verifyRemaining();
      await archive.close();
      archive = null;
      await source.cancel(operation, generation);
      _selected = false;
      checkAnalysis();
      final manifest = jsonEncode({
        'version': 1,
        'operation': operation,
        'book': book,
        'sourceSha': copied.sha256,
        'canonicalSha': await journal.canonicalDigest(book),
        'files': evidence,
      });
      final data = utf8.encode(manifest);
      if (data.length > 2097152) {
        throw const BookFailure(BookError.limitExceeded);
      }
      await files.writeStaged(
        operation,
        'manifest',
        _chunks(data),
        maxBytes: data.length,
        cancelled: () => _cancelled,
      );
      _check();
      // No await between cancellation check and disabling cancellation.
      _finalizing = true;
      update(ImportStep.finalizing, bytes: copied.bytes);
      await books.validated(
        operation,
        book,
        sha256.convert(data).toString(),
        manifest,
      );
      await BookOperationReconciler(books, journal, files).publish(
        BookOperation(
          id: operation,
          bookId: book,
          kind: BookOperationKind.import,
          phase: BookOperationPhase.validated,
          generation: generation,
        ),
      );
      update(ImportStep.complete, bytes: copied.bytes);
      return BookImportResult(
        book: Book(
          key: key,
          title: package.title,
          authors: package.authors,
          languages: package.languages,
        ),
      );
    } catch (error) {
      if (!_finalizing && began) {
        if (_selected) await source.cancel(operation, generation);
        await files.removeStaging(operation);
        await books.abandon(operation, book);
      }
      if (error is BookFailure && error.code == BookError.cancelled) {
        update(ImportStep.cancelled);
        return const BookImportResult(cancelled: true);
      }
      update(ImportStep.failed);
      if (error is BookFailure) rethrow;
      if (error is FileSystemException &&
          [28, 112].contains(error.osError?.errorCode)) {
        throw const BookFailure(BookError.insufficientStorage);
      }
      throw const BookFailure(BookError.storageUnavailable);
    } finally {
      if (archive != null) {
        try {
          await archive.close();
        } catch (_) {
          /* cancellation may already own close */
        }
      }
      _busy = false;
      _settled!.complete();
    }
  }

  Stream<List<int>> _chunks(List<int> data) async* {
    for (var n = 0; n < data.length; n += 65536) {
      yield Uint8List.fromList(
        data.sublist(n, (n + 65536).clamp(0, data.length)),
      );
    }
  }
}

Future<({String sha, ImageInspection inspection})> _imageInfo(
  Uint8List data,
) async => (
  sha: sha256.convert(data).toString(),
  inspection: ImagePolicy.inspect(data.sublist(0, data.length.clamp(0, 65536))),
);
