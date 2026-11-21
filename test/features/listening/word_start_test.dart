import 'dart:async';

import 'package:prototype/features/listening/content_source_adapter.dart';
import 'package:prototype/infrastructure/database/book_content_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/book_reader/word_selection_source.dart';

import '../audio_player/player_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('exact word excludes earlier source and keeps absolute offsets and French numbers', () async {
    final f = PlayerFixture();
    await f.open();
    addTearDown(f.close);
    final key = await f.book(
      'word-start',
      text: 'Avant, nous achetons 21 pommes. La suite.',
    );
    final selected = await WordSelectionSource.resolve(
      f.content,
      f.at(key, 0, offset: 21),
    );
    expect(selected.text, '21');
    await f.owner.playFromWord(f.context(key), selected);
    final request = f.speech.requests.first;
    expect(request.start.offsetUtf16, 21);
    expect(request.text, startsWith('21 pommes'));
    expect(request.text, isNot(contains('Avant')));
    expect(request.synthesisText, contains('Vingt-et-un'));
    await f.owner.pause();
    f.speech.complete(request.requestId);
    await f.settle();
    expect(f.player.opens, 0);
    final count = f.speech.requests.length;
    await f.owner.playFromParagraph(f.context(key), selected.start);
    expect(f.speech.requests[count].start.offsetUtf16, 0);
    expect(f.speech.requests[count].text, startsWith('Avant'));
  });
  test(
    'a stopped or foreign word intent never replaces the current owner',
    () async {
      final f = PlayerFixture();
      await f.open();
      addTearDown(f.close);
      final key = await f.book(
        'late-word',
        text: 'Avant, le jardin.',
        blocks: 1,
        chapters: 1,
      );
      final selected = await WordSelectionSource.resolve(
        f.content,
        f.at(key, 0, offset: 10),
      );
      final other = await f.book('other-word', blocks: 1, chapters: 1);
      await expectLater(
        f.owner.playFromWord(f.context(other), selected),
        throwsA(isA<BookFailure>()),
      );
      final gate = GateWordSource(f);
      final start = f.owner.playFromWord(
        BookSpeechContext(key, gate),
        selected,
      );
      await gate.entered.future;
      await f.owner.stop();
      gate.release.complete();
      await start;
      expect(f.speech.requests, isEmpty);
    },
  );
  test('cross-slice word is identified but exact v1 start is explicitly unavailable', () async {
    final f = PlayerFixture();
    await f.open();
    addTearDown(f.close);
    final k = await f.book('seam', blocks: 2, chapters: 1);
    await f.db.customStatement(
      "UPDATE book_blocks SET block_id='c0-b0-s0',source_text='Un extraor' WHERE book_id=? AND ordinal=0",
      [k.id],
    );
    await f.db.customStatement(
      "UPDATE book_blocks SET block_id='c0-b0-s1',source_text='dinaire jardin.' WHERE book_id=? AND ordinal=1",
      [k.id],
    );
    final selection = await WordSelectionSource.resolve(
      f.content,
      BookLocator(key: k, chapterId: 'c0', blockId: 'c0-b0-s0', offsetUtf16: 5),
    );
    expect(selection.text, 'extraordinaire');
    expect(selection.canStart, isFalse);
    await expectLater(
      f.owner.playFromWord(f.context(k), selection),
      throwsA(isA<BookFailure>()),
    );
    expect(f.speech.requests, isEmpty);
  });
}

class GateWordSource extends BookContentRepository {
  GateWordSource(PlayerFixture f) : super(f.db, f.content.files);
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<void> validateLocator(BookLocator locator) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    await super.validateLocator(locator);
  }
}
