import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/infrastructure/epub/android_document_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.ureader.prototype/epub/v1');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Map<String, Object?> response(MethodCall call, Map<String, Object?> result) {
    final q = Map<String, Object?>.from(call.arguments as Map);
    return {...q..remove('payload'), 'result': result};
  }

  test(
    'all cancellation callers wait for native closure before cleanup',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'chooseDocument') {
          return response(call, {'status': 'selected', 'sourceHandle': 'h'});
        }
        if (call.method == 'cancel') {
          calls++;
          if (!entered.isCompleted) {
            entered.complete();
          }
          await release.future;
          return response(call, {'cancelled': true});
        }
        throw StateError('unexpected');
      });
      final source = AndroidDocumentSource();
      await source.choose('op', 1);
      var firstDone = false, secondDone = false;
      final first = source.cancel('op', 1).then((_) {
        firstDone = true;
      });
      await entered.future;
      final second = source.cancel('op', 1).then((_) {
        secondDone = true;
      });
      await Future<void>.delayed(Duration.zero);
      final earlyFirst = firstDone, earlySecond = secondDone;
      release.complete();
      await Future.wait([first, second]);
      expect(earlyFirst, false);
      expect(earlySecond, false);
      expect(calls, 1);
      expect(firstDone && secondDone, true);
    },
  );
  test(
    'selection, bounded reads, counters, EOF and idempotent close',
    () async {
      var reads = 0;
      var closes = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'chooseDocument') {
          return response(call, {
            'status': 'selected',
            'sourceHandle': 'h1',
            'displayName': 'Mon livre.epub',
            'declaredBytes': 999,
          });
        }
        if (call.method == 'readSource') {
          reads++;
          return response(call, {
            'bytes': Uint8List.fromList([1, 2]),
            'eof': true,
            'totalBytes': 2,
          });
        }
        if (call.method == 'close') {
          closes++;
          return response(call, {'closed': true});
        }
        throw StateError('unexpected');
      });
      final source = AndroidDocumentSource();
      final handle = (await source.choose('op', 1))!;
      expect(source.selection?.displayName, 'Mon livre.epub');
      final chunk = await source.read(handle, maxBytes: 2);
      expect(chunk.totalBytes, 2);
      expect((await source.read(handle)).bytes, isEmpty);
      expect(reads, 1);
      await source.close(handle);
      await source.close(handle);
      expect(closes, 1);
      await expectLater(source.read(handle), throwsA(isA<BookFailure>()));
    },
  );
  test('invalid chunk bounds never cross platform boundary', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      return response(call, {'status': 'cancelled'});
    });
    final source = AndroidDocumentSource();
    await expectLater(
      source.read('unknown', maxBytes: 65537),
      throwsA(isA<BookFailure>()),
    );
    expect(calls, 0);
  });
  test(
    'rejects stale envelope, impossible counters and empty non-final chunks',
    () async {
      for (final mode in ['stale', 'counter', 'empty', 'oversized']) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'chooseDocument') {
            return response(call, {
              'status': 'selected',
              'sourceHandle': 'h',
              'declaredBytes': null,
            });
          }
          return response(call, {
            'bytes': Uint8List.fromList(
              mode == 'empty'
                  ? []
                  : mode == 'oversized'
                  ? [1, 2, 3]
                  : [1],
            ),
            'eof': false,
            'totalBytes': mode == 'counter' ? 0 : 1,
          })..['generation'] = mode == 'stale' ? 999 : 1;
        });
        final source = AndroidDocumentSource();
        final handle = (await source.choose('op', 1))!;
        await expectLater(
          source.read(handle, maxBytes: 2),
          throwsA(isA<BookFailure>()),
        );
      }
    },
  );
  test(
    'cancel invalidates pending selection and suppresses late success',
    () async {
      final selected = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'chooseDocument') return selected.future;
        return response(call, {'cancelled': true});
      });
      final source = AndroidDocumentSource();
      final pending = source.choose('op', 1);
      final verdict = expectLater(
        pending,
        throwsA(
          isA<BookFailure>().having((e) => e.code, 'code', BookError.cancelled),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await source.cancel('op', 1);
      selected.complete({
        'protocolVersion': 1,
        'requestId': 'late',
        'operationId': 'op',
        'generation': 1,
        'result': {'status': 'selected', 'sourceHandle': 'h'},
      });
      await verdict;
    },
  );
  test('native errors never reveal raw details', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => response(call, {})
        ..remove('result')
        ..['error'] = {
          'code': 'sourceUnavailable',
          'detail': 'content://private/book',
        },
    );
    final source = AndroidDocumentSource();
    try {
      await source.choose('op', 1);
      fail('must reject');
    } on BookFailure catch (e) {
      expect(e.code, BookError.sourceUnavailable);
      expect(e.toString(), isNot(contains('content://')));
    }
  });
  test('copy hashes actual bytes and closes only after verified EOF', () async {
    var reads = 0;
    var closed = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'chooseDocument') {
        return response(call, {
          'status': 'selected',
          'sourceHandle': 'h',
          'declaredBytes': 1000000,
        });
      }
      if (call.method == 'close') {
        closed = true;
        return response(call, {'closed': true});
      }
      reads++;
      return response(call, {
        'bytes': Uint8List.fromList(reads == 1 ? [97, 98, 99] : []),
        'eof': reads > 1,
        'totalBytes': 3,
      });
    });
    final source = AndroidDocumentSource();
    final h = (await source.choose('copy', 1))!;
    final copied = await source.copyAndHash(h);
    expect(copied.bytes, 3);
    expect(
      copied.sha256,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(closed, true);
  });
  test(
    'archive pages and every unselected entry are actually drained',
    () async {
      final readHandles = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        final q = call.arguments as Map;
        final payload = q['payload'] as Map;
        switch (call.method) {
          case 'chooseDocument':
            return response(call, {'status': 'selected', 'sourceHandle': 's'});
          case 'openArchive':
            return response(call, {'archiveHandle': 'a', 'entryCount': 2});
          case 'listEntries':
            return response(call, {
              'entries': [
                for (final n in ['one', 'unused'])
                  {
                    'entryHandle': n,
                    'logicalName': n,
                    'compressedBytes': 1,
                    'declaredBytes': 1,
                    'directory': false,
                  },
              ],
              'nextCursor': null,
              'done': true,
            });
          case 'readEntry':
            readHandles.add(payload['entryHandle'] as String);
            return response(call, {
              'bytes': Uint8List.fromList([65]),
              'eof': true,
              'totalBytes': 1,
            });
          case 'close':
            return response(call, {'closed': true});
        }
        throw StateError('unexpected');
      });
      final source = AndroidDocumentSource();
      await source.choose('archive', 1);
      final archive = await source.openArchive();
      expect(await archive.read('one', maxBytes: 10), [65]);
      await archive.verifyRemaining();
      expect(readHandles, ['one', 'unused']);
      await expectLater(
        archive.read('one', maxBytes: 0),
        throwsA(isA<BookFailure>()),
      );
      await archive.close();
    },
  );
  test(
    'independent clients never share an in-flight request identity',
    () async {
      final ids = <String>{};
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final raw = call.arguments as Map;
        expect(ids.add(raw['requestId'] as String), true);
        calls++;
        return response(call, {'status': 'cancelled'});
      });
      await Future.wait([
        AndroidDocumentSource().choose('one', 1),
        AndroidDocumentSource().choose('two', 1),
      ]);
      expect(calls, 2);
      expect(ids.length, 2);
    },
  );
}
