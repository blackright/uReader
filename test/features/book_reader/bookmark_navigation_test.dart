import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/features/book_reader/bookmark_controller.dart';
import 'package:prototype/features/book_reader/book_reader_controller.dart';
import 'package:prototype/infrastructure/database/bookmark_repository.dart';

import '../audio_player/player_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('bookmark consultation preserves audio and survives presentation changes without follow', () async {
    final f = PlayerFixture();
    await f.open();
    addTearDown(f.close);
    final key = await f.book('marks-audio');
    final reader = BookReaderController(
      book: Book(key: key, title: 'Livre', authors: [], languages: ['fr']),
      content: f.content,
      playback: f.owner,
    );
    await reader.initialize();
    final store = BookmarkRepository(f.db, f.content);
    final marks = BookmarkController(reader, store);
    addTearDown(marks.dispose);
    addTearDown(reader.close);
    await marks.addParagraph(f.at(key, 1));
    expect(marks.entries.length, 1);
    await f.owner.playFromParagraph(f.context(key), f.at(key, 0));
    await f.owner.pause();
    final generation = f.owner.sessionGeneration,
        requests = f.speech.requests.length;
    await reader.changePreferences(
      ReaderPreferences(fontScale: 1.5, theme: ReaderTheme.dark),
    );
    expect(await marks.open(marks.entries.single.bookmark), isTrue);
    expect(reader.focusLocator!.blockId, 'b1');
    expect(f.owner.sessionGeneration, generation);
    expect(f.speech.requests.length, requests);
    await marks.addParagraph(f.at(key, 1));
    expect(marks.entries.length, 1);
    expect(marks.status, contains('déjà'));
  });
  test('image-only page proposes a named neighboring text, without automatic write', () async {
    final f = PlayerFixture();
    await f.open();
    addTearDown(f.close);
    final key = await f.book('image-marks');
    await f.db.customStatement(
      "UPDATE book_blocks SET kind='image',source_text='',text_units=0,speech_eligible=0 WHERE book_id=? AND ordinal=0",
      [key.id],
    );
    final reader = BookReaderController(
      book: Book(key: key, title: 'Images', authors: [], languages: ['fr']),
      content: f.content,
    );
    await reader.initialize();
    final store = BookmarkRepository(f.db, f.content);
    final marks = BookmarkController(reader, store);
    addTearDown(marks.dispose);
    addTearDown(reader.close);
    await marks.addVisible();
    expect(marks.proposal, isNotNull);
    expect((await store.list(key)).items, isEmpty);
    expect(reader.visible!.blockId, 'b0');
    await marks.confirmProposal();
    expect((await store.list(key)).items.single.locator.blockId, 'b1');
  });
  test(
    'invalid bookmark has an explicit fallback and storage retry is honest',
    () async {
      final f = PlayerFixture();
      await f.open();
      addTearDown(f.close);
      final key = await f.book('retry');
      final reader = BookReaderController(
        book: Book(key: key, title: 'Repli', authors: [], languages: ['fr']),
        content: f.content,
      );
      await reader.initialize();
      final store = BookmarkRepository(f.db, f.content);
      var suspended = 0;
      final marks = BookmarkController(
        reader,
        store,
        suspendFollow: () => suspended++,
      );
      addTearDown(marks.dispose);
      addTearDown(reader.close);
      await f.db.customStatement(
        "CREATE TRIGGER deny_marks BEFORE INSERT ON book_bookmarks BEGIN SELECT RAISE(ABORT,'denied'); END",
      );
      await marks.addVisible();
      expect(marks.error, isNotNull);
      expect(marks.entries, isEmpty);
      expect(marks.status, isNull);
      await f.db.customStatement('DROP TRIGGER deny_marks');
      await marks.retry();
      expect(marks.entries.length, 1);
      final mark = marks.entries.single.bookmark;
      await f.db.customStatement(
        'UPDATE book_bookmarks SET offset_utf16=999 WHERE bookmark_id=?',
        [mark.id],
      );
      await marks.load();
      expect(await marks.open(marks.entries.single.bookmark), isFalse);
      expect(marks.fallback, isNotNull);
      expect(reader.visible!.blockId, 'b0');
      await marks.openFallback();
      expect(suspended, 1);
    },
  );
}
