import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';

import 'player_fixture.dart';

import 'package:prototype/features/book_reader/book_reader_controller.dart';

import 'package:prototype/features/audio_player/content_target_controller.dart';
import 'package:prototype/infrastructure/audio/system_audio_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('logical paragraphs, cross chapter, silent paused/stopped seeks and boundaries', () async {
    final f = PlayerFixture();
    await f.open();
    addTearDown(f.close);
    final k = await f.book('commands', blocks: 4, text: 'Bonjour.');
    await f.db.customStatement(
      "UPDATE book_blocks SET block_id='c0-b0-s0' WHERE book_id=? AND ordinal=0",
      [k.id],
    );
    await f.db.customStatement(
      "UPDATE book_blocks SET block_id='c0-b0-s1' WHERE book_id=? AND ordinal=1",
      [k.id],
    );
    await f.owner.playFromParagraph(
      f.context(k),
      f.at(k, 1, id: 'c0-b0-s1', offset: 3),
    );
    expect(f.owner.targetLocator!.blockId, 'c0-b0-s0');
    f.speech.complete(f.speech.requests.last.requestId);
    await f.settle();
    expect(f.owner.state, PlaybackState.playing);
    await f.owner.pause();
    final opens = f.player.opens;
    expect(await f.owner.moveParagraph(true), isTrue);
    expect(f.owner.targetLocator!.blockId, 'b2');
    expect(f.owner.state, PlaybackState.paused);
    expect(f.player.opens, opens);
    await f.owner.stop();
    await f.owner.moveParagraph(true);
    expect(f.owner.targetLocator!.blockId, 'b3');
    expect(f.owner.state, PlaybackState.stopped);
    expect(f.player.playing, isFalse);
    expect(await f.owner.moveParagraph(true), isFalse);
    expect(f.owner.bookNotice, isNotNull);
    await expectLater(
      f.owner.seekParagraph(
        f.at(ContentKey(ContentKind.book, 'foreign', 1), 0),
      ),
      throwsA(isA<BookFailure>()),
    );
    expect(f.owner.bookKey, k);
    await f.owner.moveParagraph(false);
    expect(f.owner.targetLocator!.blockId, 'b2');
  });
  test(
    'stale selection cannot restart after stop or replace a newer owner',
    () async {
      final f = PlayerFixture();
      await f.open();
      addTearDown(f.close);
      final a = await f.book('a', blocks: 4), b = await f.book('b', blocks: 4);
      final pending = f.owner.playFromParagraph(f.context(a), f.at(a, 0));
      await f.owner.stop();
      await pending;
      expect(f.speech.requests, isEmpty);
      await f.owner.playFromParagraph(f.context(b), f.at(b, 0));
      expect(f.owner.bookKey, b);
      expect(f.owner.targetLocator!.key, b);
    },
  );
  test('content targets are bounded, preview-only and confirm with current transport state', () async {
    final f = PlayerFixture();
    await f.open();
    addTearDown(f.close);
    final key = await f.book(
      'targets',
      blocks: 60,
      chapters: 2,
      text: 'Texte de contenu.',
    );
    final model = ContentTargetController(key, f.content);
    addTearDown(model.dispose);
    await model.initialize();
    expect(model.choices.length, 25);
    expect(model.nextOrdinal, isNotNull);
    await model.selectProgress(.8);
    expect(model.selected!.locator.chapterId, 'c1');
    final actual = (await f.content.progress(model.selected!.locator));
    expect(model.actualProgress, actual.$1 / actual.$2);
    expect(f.speech.requests, isEmpty);
    final selected = model.selected!.locator;
    await f.owner.playFromParagraph(f.context(key), f.at(key, 0));
    await f.owner.pause();
    await f.owner.seekParagraph(selected);
    expect(f.owner.targetLocator!.blockId, selected.blockId);
    expect(f.owner.state, PlaybackState.paused);
    expect(f.player.opens, 0);
  });
  test('Android transport and metadata use the existing owner', () async {
    final f = PlayerFixture();
    await f.open();
    addTearDown(f.close);
    final key = await f.book('system', blocks: 4);
    final handler = SystemAudioHandler(f.owner);
    addTearDown(handler.close);
    await f.owner.playFromParagraph(f.context(key), f.at(key, 0));
    await handler.pause();
    f.owner.publishBookMetadata(
      key,
      title: 'Le jardin',
      author: 'Camille',
      chapter: 'Le départ',
    );
    expect(handler.mediaItem.value!.title, 'Le jardin');
    expect(handler.mediaItem.value!.artist, 'Camille');
    await handler.skipToNext();
    expect(f.owner.targetLocator!.blockId, 'b1');
    expect(f.player.opens, 0);
    await handler.skipToPrevious();
    expect(f.owner.targetLocator!.blockId, 'b0');
    await handler.stop();
    expect(f.owner.state, PlaybackState.stopped);
  });
  test(
    'reader surfaces an invalid audio target without changing owner',
    () async {
      final f = PlayerFixture();
      await f.open();
      addTearDown(f.close);
      final key = await f.book('reader-error');
      final reader = BookReaderController(
        book: Book(key: key, title: 'Livre', authors: [], languages: ['fr']),
        content: f.content,
        playback: f.owner,
      );
      await reader.initialize();
      await reader.listenHere(
        from: f.at(ContentKey(ContentKind.book, 'foreign', 1), 0),
      );
      expect(reader.narrationMessage, isNotNull);
      expect(f.owner.bookKey, isNull);
      expect(f.speech.requests, isEmpty);
      await reader.close();
    },
  );
}
