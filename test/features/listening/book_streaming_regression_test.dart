import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/features/listening/content_source_adapter.dart';
import 'package:prototype/features/listening/book_segment_cursor.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';
import 'package:prototype/infrastructure/epub/epub_projection_worker.dart';

class Lease implements ContentLease {
  bool released = false;
  @override
  Future<void> release() async {
    released = true;
  }
}

class ProjectedSource implements BookNavigationSource {
  ProjectedSource(this.key, this.blocks);
  final ContentKey key;
  final List<BookBlock> blocks;
  final lease = Lease();
  int reads = 0;
  Completer<BookWindow>? pending;
  @override
  Future<ContentLease> acquire(ContentKey key) async => lease;
  @override
  Future<BookWindow> window(
    ContentKey key,
    int generation, {
    BookCursor? after,
    int maxBlocks = 64,
    int maxUnits = 65536,
  }) async {
    reads++;
    expect(maxBlocks, 1);
    if (pending != null) return pending!.future;
    final ordinal = after?.nextOrdinal ?? 0;
    return BookWindow(
      key: key,
      generation: generation,
      blocks: ordinal >= blocks.length ? [] : [blocks[ordinal]],
      next: ordinal + 1 < blocks.length
          ? BookCursor(
              key: key,
              generation: generation,
              nextOrdinal: ordinal + 1,
            )
          : null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a single long XHTML body is projected once and audio only pulls its first block', () async {
    final key = ContentKey(ContentKind.book, 'single-body', 1);
    final result = await EpubProjectionWorker.projectString(
      key: key,
      chapterOrdinal: 0,
      xhtml: '<html><body><p>${'Bonjour le jardin. ' * 2000}</p></body></html>',
    );
    expect(result.blocks.length, greaterThan(1));
    final source = ProjectedSource(key, result.blocks);
    var tokenCalls = 0;
    final cursor = BookSegmentCursor(
      BookSpeechContext(key, source),
      SpeechSegmenter((s) async {
        tokenCalls++;
        return s.split(' ').length;
      }),
    );
    expect(await cursor.next(), isNotNull);
    expect(source.reads, 1);
    expect(tokenCalls, lessThan(30));
    expect(cursor.retainedBlocks, 1);
    await cursor.close();
    expect(source.lease.released, isTrue);
  });
  test('closing during a content load prevents a late segment and releases the lease', () async {
    final key = ContentKey(ContentKind.book, 'delayed-body', 1);
    final source = ProjectedSource(key, [])..pending = Completer<BookWindow>();
    final cursor = BookSegmentCursor(
      BookSpeechContext(key, source),
      SpeechSegmenter((s) async => 1),
    );
    final future = cursor.next();
    for (var i = 0; i < 10 && source.reads == 0; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(source.reads, 1);
    await cursor.close();
    source.pending!.complete(BookWindow(key: key, generation: 1, blocks: []));
    expect(await future, isNull);
    expect(source.lease.released, isTrue);
    expect(cursor.retainedBlocks, 0);
  });
}
