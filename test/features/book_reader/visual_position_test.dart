import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/infrastructure/database/book_position_repository.dart';
import 'package:prototype/infrastructure/database/book_preferences_repository.dart';

import 'reader_fixture.dart';

void main() {
  late ReaderFixture f;
  setUp(() async {
    f = ReaderFixture();
    await f.open();
  });
  tearDown(() async {
    await f.close();
  });
  test('five locators across three books survive presentation changes and do not write audio', () async {
    final positions = BookPositionRepository(f.db, f.content),
        prefs = BookPreferencesRepository(f.db);
    final keys = [
      for (final id in ['one', 'two', 'three']) await f.book(id),
    ];
    for (var i = 0; i < 5; i++) {
      final key = keys[i % 3],
          old = await positions.read(keys[i % 3], ReadingMode.visual);
      final where = BookLocator(
        key: key,
        chapterId: 'c0',
        blockId: 'b${i % 4}',
        offsetUtf16: 0,
      );
      final saved = await positions.save(
        where,
        ReadingMode.visual,
        expectedRevision: old?.revision ?? 0,
      );
      await prefs.save(
        ReaderPreferences(fontScale: 1.5, theme: ReaderTheme.dark),
      );
      expect(
        (await BookPositionRepository(
          f.db,
          f.content,
        ).read(key, ReadingMode.visual))!.locator.blockId,
        where.blockId,
      );
      await expectLater(
        positions.save(where, ReadingMode.visual, expectedRevision: 0),
        throwsA(isA<BookFailure>()),
      );
      expect(saved.revision, (old?.revision ?? 0) + 1);
      await expectLater(
        positions.save(where, ReadingMode.audio, expectedRevision: 0),
        throwsA(isA<BookFailure>()),
      );
    }
    expect(
      (await f.db
          .customSelect("SELECT * FROM book_positions WHERE mode='audio'")
          .get()),
      isEmpty,
    );
    expect((await BookPreferencesRepository(f.db).read()).fontScale, 1.5);
    final key = keys.first;
    final old = (await positions.read(key, ReadingMode.visual))!;
    await f.db.customStatement(
      "CREATE TRIGGER reject_visual BEFORE UPDATE ON book_positions BEGIN SELECT RAISE(ABORT,'injected'); END",
    );
    await expectLater(
      positions.save(
        old.locator,
        ReadingMode.visual,
        expectedRevision: old.revision,
      ),
      throwsA(isA<BookFailure>()),
    );
    expect(
      (await positions.read(key, ReadingMode.visual))!.revision,
      old.revision,
    );
  });
}
