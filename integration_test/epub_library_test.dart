// Real SAF + native ZIP + production importer/repositories. Only CC0 test books.
// The product database and voice are never opened or cleared by this campaign.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/library/book_importer.dart';
import 'package:prototype/infrastructure/database/book_content_repository.dart';
import 'package:prototype/infrastructure/database/book_operation_repository.dart';
import 'package:prototype/infrastructure/database/book_repository.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/epub/android_document_source.dart';
import 'package:prototype/infrastructure/epub/search_key_normalizer.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';
import 'package:prototype/infrastructure/files/book_operation_reconciler.dart';

import 'feasibility_bootstrap.dart';
import 'epub_library_management_test.dart' show registerLibraryManagementTests;

class NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Network forbidden during EPUB validation');
  }
}

class FaultBooks extends BookRepository {
  FaultBooks(super.db, this.point, this.files);
  final String? point;
  final BookFileStore files;
  @override
  Future<void> validated(
    String op,
    String book,
    String digest,
    String proof,
  ) async {
    if (point == 'before-validated') throw StateError('injected interruption');
    await super.validated(op, book, digest, proof);
    if (point == 'tampered') {
      await (await files.stagingFile(op, 'source')).writeAsBytes([9]);
    }
    if (point == 'validated' || point == 'tampered') {
      throw StateError('injected interruption');
    }
  }

  @override
  Future<void> commitReady(String op, String book, String digest) async {
    if (point == 'renamed') throw StateError('injected interruption');
    await super.commitReady(op, book, digest);
    if (point == 'committed') throw StateError('injected interruption');
  }
}

class AuditedChannel extends MethodChannel {
  AuditedChannel(this.events) : super('com.ureader.prototype/epub/v1');
  final List<Map<String, Object?>> events;
  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    final result = await super.invokeMethod<T>(method, arguments);
    if (result is Map) {
      final data = result['result'];
      events.add({
        'method': method,
        'error': result['error'],
        'status': data is Map ? data['status'] : null,
        'cancelled': data is Map ? data['cancelled'] : null,
      });
    }
    return result;
  }
}

class DeviceSource extends AndroidDocumentSource {
  DeviceSource(List<Map<String, Object?>> events)
    : super(channel: AuditedChannel(events));
  bool loseAfterSelection = false;
  @override
  Future<({String sha256, int bytes})> copyAndHash(
    String handle, {
    void Function(int)? progress,
  }) async {
    if (loseAfterSelection) {
      await cancel(selectionOperation!, 1);
      throw const BookFailure(BookError.sourceUnavailable);
    }
    return super.copyAndHash(handle, progress: progress);
  }

  String? selectionOperation;
  @override
  Future<String?> choose(String operationId, int generation) {
    selectionOperation = operationId;
    return super.choose(operationId, generation);
  }
}

Future<int> bytesUnder(Directory directory) async {
  if (!await directory.exists()) return 0;
  var bytes = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File) bytes += await entity.length();
  }
  return bytes;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerLibraryManagementTests(binding);
  testWidgets('US1 real document import, recovery and hostile corpus', (
    tester,
  ) async {
    await waitForNative(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text(
            'Validation bibliothèque en cours. Ne pas utiliser le téléphone.',
          ),
        ),
      ),
    );
    final report = <String, Object?>{};
    await tester.runAsync(() async {
      final support = await getApplicationSupportDirectory();
      final root = Directory(
        p.join(await support.resolveSymbolicLinks(), 'ureader-prototype'),
      );
      final config = jsonDecode(
        await File(p.join(root.path, 'us1-validation-config.json'))
            .readAsString(),
      ) as Map;
      final request = File(p.join(root.path, 'us1-validation-request.json'));
      final resultFile = File(p.join(root.path, 'us1-validation-result.json'));
      final run = 'us1val-${DateTime.now().microsecondsSinceEpoch}';
      final databaseFile = File(p.join(root.path, '$run.sqlite'));
      var db = PrototypeDatabase(NativeDatabase(databaseFile));
      await db.initialize();
      final files = await BookFileStore.open(root);
      final originalHttp = HttpOverrides.current;
      final guard = NoNetwork();
      HttpOverrides.global = guard;
      final protocolEvents = <Map<String, Object?>>[];
      final ownedBooks = <String>[], ownedOps = <String>[];
      final ids = <String, String>{}, rows = <Map<String, Object?>>[];
      final rss = <int>[];
      var seq = 0;
      Future<void> issue(Map<String, Object?> body) async {
        final part = File('${request.path}.part');
        await part.writeAsString(jsonEncode(body));
        await part.rename(request.path);
      }

      try {
        for (final raw in config['cases'] as List) {
          // Let the system picker finish its Activity/search teardown before reuse.
          await Future<void>.delayed(const Duration(seconds: 3));
          final entry = raw as Map;
          final caseId = entry['id'] as String,
              policy = entry['policy'] as String;
          final op = '$run-op-${++seq}', id = '$run-book-$seq';
          ownedOps.add(op);
          ownedBooks.add(id);
          final books = FaultBooks(db, entry['checkpoint'] as String?, files);
          final source = DeviceSource(protocolEvents)
            ..loseAfterSelection = policy == 'lost';
          final normalizer = SearchKeyNormalizer();
          final importer = BookImporter(
            source: source,
            books: books,
            files: files,
            normalizeKey: normalizer.normalize,
          );
          final beforeReady = (await books.readyPage())
              .map((b) => b.key.id)
              .toSet();
          final positionsBefore = jsonEncode(
            (await db
                    .customSelect(
                      'SELECT * FROM book_positions ORDER BY book_id,mode',
                    )
                    .get())
                .map((r) => r.data)
                .toList(),
          );
          final beforeRss = ProcessInfo.currentRss;
          final watch = Stopwatch()..start();
          Stopwatch? cancellation;
          int? copyStartedMs;
          var timerSamples = 0, maxTimerLagUs = 0, previousTickUs = 0;
          final eventClock = Stopwatch();
          Timer? eventProbe;
          var bytesCopied = 0;
          BookImportResult? result;
          BookFailure? failure;
          await issue({
            'sequence': seq,
            'action': 'select',
            'filename': entry['filename'],
          });
          try {
            result = await importer.importBook(
              op,
              id,
              1,
              progress: (progress) {
                if (progress.step == ImportStep.copying && eventProbe == null) {
                  copyStartedMs = watch.elapsedMilliseconds;
                  eventClock.start();
                  eventProbe = Timer.periodic(
                    const Duration(milliseconds: 20),
                    (_) {
                      final now = eventClock.elapsedMicroseconds;
                      final lag = now - previousTickUs - 20000;
                      if (lag > maxTimerLagUs) maxTimerLagUs = lag;
                      previousTickUs = now;
                      timerSamples++;
                    },
                  );
                }
                if (progress.bytes > bytesCopied) bytesCopied = progress.bytes;
                if (policy == 'cancel' &&
                    progress.step == ImportStep.copying &&
                    progress.bytes > 0 &&
                    cancellation == null) {
                  cancellation = Stopwatch()..start();
                  unawaited(importer.cancel());
                }
              },
            );
          } on BookFailure catch (error) {
            failure = error;
          }
          eventProbe?.cancel();
          await importer.shutdown();
          final cancelMs = cancellation?.elapsedMilliseconds;
          // Close/reopen the on-disk test DB, then run production recovery twice.
          await db.close();
          db = PrototypeDatabase(NativeDatabase(databaseFile));
          await db.initialize();
          final reopened = BookRepository(db);
          final reconciler = BookOperationReconciler(
            reopened,
            BookOperationRepository(db),
            files,
          );
          final recoveryIssues = await reconciler.recover();
          await reconciler.recover();
          final ready = await reopened.readyPage();
          expect(
            jsonEncode(
              (await db
                      .customSelect(
                        'SELECT * FROM book_positions ORDER BY book_id,mode',
                      )
                      .get())
                  .map((r) => r.data)
                  .toList(),
            ),
            positionsBefore,
            reason: 'positions preserved by $caseId',
          );
          expect(
            ready.map((b) => b.key.id).toSet().containsAll(beforeReady),
            true,
            reason: '$caseId preserves previously ready books',
          );
          final row = <String, Object?>{
            'id': caseId,
            'policy': policy,
            'elapsedMs': watch.elapsedMilliseconds,
            'copyThroughRecoveryMs': copyStartedMs == null
                ? null
                : watch.elapsedMilliseconds - copyStartedMs!,
            'timerSamplesDuringImport': timerSamples,
            'maxImportEventLoopTimerLagUs': timerSamples == 0
                ? null
                : maxTimerLagUs,
            'copiedBytes': bytesCopied,
            'rssBefore': beforeRss,
            'rssAfter': ProcessInfo.currentRss,
            'cancellationMs': cancelMs,
            'error': failure?.code.name,
            'recoveryIssues': recoveryIssues.map((e) => e.code.name).toList(),
          };
          rss.add(ProcessInfo.currentRss);
          if (policy == 'reject' || policy == 'lost' || policy == 'cancel') {
            expect(ready.length, beforeReady.length, reason: caseId);
            if (policy == 'cancel') {
              expect(result?.cancelled, true);
              expect(cancelMs, isNotNull);
            } else {
              expect(failure, isNotNull, reason: caseId);
            }
          } else if (policy == 'interrupt') {
            final recovered = [
              'validated',
              'renamed',
              'committed',
            ].contains(entry['checkpoint']);
            expect(
              ready.length,
              beforeReady.length + (recovered ? 1 : 0),
              reason: caseId,
            );
            expect(failure, isNotNull);
            row['recoveredReady'] = recovered;
          } else {
            expect(failure, isNull, reason: caseId);
            expect(result?.book, isNotNull, reason: caseId);
            if (policy == 'existing') {
              expect(result!.existing, true);
              expect(result.book!.key.id, ids[entry['original']]);
              expect(ready.length, beforeReady.length);
            } else {
              expect(ready.length, beforeReady.length + 1, reason: caseId);
              ids[caseId] = id;
              if (policy == 'edition') {
                expect(result!.book!.title, entry['expectedTitle']);
              }
            }
            final content = BookContentRepository(db, files);
            final book = result!.book!;
            final chapters = await content.chapters(book.key);
            expect(chapters, isNotEmpty);
            final actual = <String, String>{};
            BookCursor? after;
            do {
              final window = await content.window(book.key, 1, after: after);
              expect(window.blocks.length, lessThanOrEqualTo(64));
              expect(
                window.blocks.fold<int>(0, (n, b) => n + b.text.length),
                lessThanOrEqualTo(65536),
              );
              actual.addAll({for (final b in window.blocks) b.id: b.text});
              after = window.next;
            } while (after != null);
            expect(actual.values.join(), isNotEmpty);
            if (entry['reference'] case final Map reference) {
              expect(chapters.length, (reference['chapters'] as List).length);
              for (final chapter in reference['chapters'] as List) {
                for (final block in chapter['initialCanonicalBlocks'] as List) {
                  expect(
                    actual[block['id']],
                    block['text'],
                    reason: '$caseId ${block['id']}',
                  );
                }
              }
            }
            if (caseId.contains('image-20mp')) {
              final resources = await db
                  .customSelect(
                    "SELECT * FROM book_resources WHERE book_id='$id'",
                  )
                  .get();
              expect(
                resources.isNotEmpty &&
                    resources.every((r) => r.data['state'] == 'placeholder'),
                true,
              );
            }
            expect(
              (await (await files.bookFile(
                book.key.id,
                'source',
              )).openRead().transform(sha256).first).toString(),
              entry['sha256'],
            );
            if (policy == 'ready') {
              final first = (await content.window(book.key, 1)).blocks.first;
              await db.customStatement(
                'INSERT INTO book_positions(book_id,mode,projection_version,chapter_id,block_id,offset_utf16,revision,updated_at) VALUES (?, ?, 1, ?, ?, 0, 1, 1)',
                [book.key.id, 'visual', first.chapterId, first.id],
              );
            }
            row['blocksRead'] = actual.length;
          }
          row['status'] = 'passed';
          rows.add(row);
          row['databaseLogicalBytes'] = await databaseFile.length();
          row['ownedLogicalBytes'] = await bytesUnder(
            Directory(p.join(root.path, 'books', id)),
          );
          await resultFile.writeAsString(
            jsonEncode({'status': 'running', 'cases': rows}),
          );
        }
        // Make all selected originals unavailable, then read the private copies.
        await issue({'sequence': ++seq, 'action': 'hide-originals'});
        final ack = File(p.join(root.path, 'us1-validation-ack.json'));
        final wait = Stopwatch()..start();
        while (true) {
          if (await ack.exists() &&
              (jsonDecode(await ack.readAsString()) as Map)['sequence'] ==
                  seq) {
            break;
          }
          if (wait.elapsed > const Duration(seconds: 60)) {
            throw StateError('host acknowledgment timeout');
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        await db.close();
        db = PrototypeDatabase(NativeDatabase(databaseFile));
        await db.initialize();
        for (final id in ids.values) {
          final content = BookContentRepository(db, files);
          final key = ContentKey(ContentKind.book, id, 1);
          expect((await content.window(key, 1)).blocks, isNotEmpty);
        }
        expect(guard.attempts, 0);
        report.addAll({
          'status': 'passed',
          'cases': rows,
          'realSafSelections': rows.length,
          'reopenedWithoutOriginals': ids.length,
          'httpClientCreationsInImportIsolate': guard.attempts,
          'packetCapturePerformed': false,
          'processKillPerformed': false,
          'faults':
              'repository boundary injections with real database close/reopen',
          'rssSamples': rss,
          'rssIsPeakMeasurement': false,
          'voiceInitialized': false,
          'productDatabaseOpened': false,
          'platform': Platform.operatingSystemVersion,
        });
      } finally {
        HttpOverrides.global = originalHttp;
        await db.close();
        for (final op in ownedOps) {
          await files.removeStaging(op);
        }
        for (final id in ownedBooks) {
          await files.removeBook(id);
        }
        await issue({'sequence': ++seq, 'action': 'restore-originals'});
        for (final suffix in ['', '-wal', '-shm']) {
          final f = File('${databaseFile.path}$suffix');
          if (await f.exists()) await f.delete();
        }
        await resultFile.writeAsString(
          jsonEncode(
            report.isEmpty
                ? {
                    'status': 'failed',
                    'cases': rows,
                    'protocolEvents': protocolEvents,
                  }
                : report,
          ),
        );
      }
    });
    binding.reportData = {...?binding.reportData, ...report};
  }, timeout: const Timeout(Duration(minutes: 30)));
}
