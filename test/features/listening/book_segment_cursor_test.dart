import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/listening/book_segment_cursor.dart';
import 'package:prototype/features/listening/content_source_adapter.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';

import '../book_reader/reader_fixture.dart';

void main() {
  test(
    'book cursor skips notes, crosses chapters and preserves source offsets',
    () async {
      final f = ReaderFixture();
      await f.open();
      addTearDown(f.close);
      final key = await f.book(
        'spoken',
        blocks: 8,
        text: 'Le 21 avril, Léa lit. Puis elle sourit.',
      );
      await f.db.customStatement(
        "UPDATE book_blocks SET speech_eligible=0 WHERE block_id='b2'",
      );
      final context = BookSpeechContext(key, f.content);
      final cursor = BookSegmentCursor(
        context,
        SpeechSegmenter((s) async => s.split(' ').length),
      );
      final seen = <String>{};
      var count = 0;
      while (true) {
        final segment = await cursor.next();
        if (segment == null) break;
        final start = await context.toBook(segment.start);
        final block = await f.content.block(key, start.blockId);
        expect(
          segment.source,
          block.text.substring(
            segment.start.offsetUtf16,
            segment.end.offsetUtf16,
          ),
        );
        expect(segment.synthesis.length, lessThanOrEqualTo(4096));
        expect(segment.synthesis.split(' ').length, lessThanOrEqualTo(50));
        seen.add(start.blockId);
        count++;
      }
      expect(seen, {'b0', 'b1', 'b3', 'b4', 'b5', 'b6', 'b7'});
      expect(
        count,
        7,
      ); // Both short sentences fit together in each eligible block.
      expect(await cursor.next(), isNull);
      await cursor.close();
    },
  );
  test('first segment of a long book does not segment the rest; cancelled cursor stays closed', () async {
    final f = ReaderFixture();
    await f.open();
    addTearDown(f.close);
    final key = await f.book(
      'long-spoken',
      blocks: 1500,
      text: 'Bonjour. ' * 500,
    );
    var tokens = 0;
    final context = BookSpeechContext(key, f.content);
    final cursor = BookSegmentCursor(
      context,
      SpeechSegmenter((s) async {
        tokens++;
        return s.split(' ').length;
      }),
    );
    expect((await cursor.next())!.start.passageId, 'b0');
    expect(tokens, lessThan(30));
    expect(cursor.retainedBlocks, 1);
    await cursor.close();
    expect(await cursor.next(), isNull);
    expect(cursor.retainedBlocks, 0);
    expect(
      () => context.toWire(
        BookLocator(
          key: ContentKey(ContentKind.book, 'other', 1),
          chapterId: 'c0',
          blockId: 'b0',
          offsetUtf16: 0,
        ),
      ),
      throwsA(isA<BookFailure>()),
    );
  });
}
