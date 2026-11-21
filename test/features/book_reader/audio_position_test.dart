import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/infrastructure/database/book_position_repository.dart';

import 'reader_fixture.dart';

void main() {
  test('audio CAS writes stay separate from visual and stale callbacks write nothing', () async {
    final f = ReaderFixture();
    await f.open();
    addTearDown(f.close);
    final key = await f.book('audio-book');
    final repo = BookPositionRepository(f.db, f.content);
    BookLocator at(int i) =>
        BookLocator(key: key, chapterId: 'c0', blockId: 'b$i', offsetUtf16: 0);
    await repo.save(at(0), ReadingMode.visual, expectedRevision: 0);
    expect(
      await repo.saveAudio(at(1), expectedRevision: 0, isCurrent: () => false),
      isNull,
    );
    expect(await repo.read(key, ReadingMode.audio), isNull);
    await repo.saveAudio(at(1), expectedRevision: 0, isCurrent: () => true);
    expect((await repo.read(key, ReadingMode.audio))!.locator.blockId, 'b1');
    expect((await repo.read(key, ReadingMode.visual))!.locator.blockId, 'b0');
    await expectLater(
      repo.saveAudio(at(2), expectedRevision: 0, isCurrent: () => true),
      throwsA(isA<BookFailure>()),
    );
    await f.db.customStatement(
      "CREATE TRIGGER reject_audio BEFORE UPDATE ON book_positions WHEN NEW.mode='audio' BEGIN SELECT RAISE(ABORT,'injected'); END",
    );
    await expectLater(
      repo.saveAudio(at(2), expectedRevision: 1, isCurrent: () => true),
      throwsA(isA<BookFailure>()),
    );
    expect((await repo.read(key, ReadingMode.audio))!.locator.blockId, 'b1');
  });
}
