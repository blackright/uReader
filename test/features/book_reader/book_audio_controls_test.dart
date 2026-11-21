import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/features/book_reader/book_reader_controller.dart';
import 'package:prototype/features/book_reader/book_reader_screen.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';
import 'package:prototype/infrastructure/database/book_position_repository.dart';

import '../listening/playback_coordinator_test.dart'
    show RecordingSpeech, RecordingPlayer;
import 'reader_fixture.dart';
import 'paged_reader_screen_test.dart' show runReaderOperation;
import 'reader_presentation_test.dart' show ready;

void main() {
  testWidgets(
    'ambiguous language cancellation never starts speech, at large system text scale',
    (tester) async {
      final f = ReaderFixture();
      await tester.runAsync(f.open);
      addTearDown(f.close);
      final key = (await tester.runAsync(() => f.book('ambiguous')))!;
      final pair = (await tester.runAsync(
        () async => (RecordingSpeech(), RecordingPlayer()),
      ))!;
      final speech = pair.$1, player = pair.$2;
      final owner = (await tester.runAsync(
        () async => PlaybackCoordinator(
          speech: speech,
          player: player,
          segmenter: SpeechSegmenter((s) async => 1),
          prepareEngine: () async {},
          discardAudio: (_) async {},
        ),
      ))!;
      final book = Book(key: key, title: 'Livre', authors: [], languages: []);
      final reader = BookReaderController(
        book: book,
        content: f.content,
        playback: owner,
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(3.2)),
            child: child!,
          ),
          home: BookReaderScreen(
            book: book,
            content: f.content,
            controller: reader,
          ),
        ),
      );
      await ready(tester, reader);
      await tester.runAsync(() => tester.tap(find.text('Écouter ici')));
      await tester.pumpAndSettle();
      expect(find.text('Lire en français ?'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(speech.requests, isEmpty);
      expect(player.opens, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await runReaderOperation(tester, reader.close);
      await runReaderOperation(tester, owner.close);
    },
  );
  test('consultation changes visual only, heard navigation is explicit, English remains visual', () async {
    final f = ReaderFixture();
    await f.open();
    addTearDown(f.close);
    final key = await f.book('read-and-listen', text: 'Bonjour. La suite.');
    final positions = BookPositionRepository(f.db, f.content);
    final speech = RecordingSpeech(), player = RecordingPlayer();
    var revision = 0;
    final owner = PlaybackCoordinator(
      speech: speech,
      player: player,
      segmenter: SpeechSegmenter((s) async => s.split(' ').length),
      prepareEngine: () => speech.loadBundle(
        BundleDescriptor(
          id: 'fr-official-aligned',
          version: 'v1',
          manifestDigest: 'a' * 64,
          files: [
            BundleFile(relativePath: 'model', byteSize: 1, sha256: 'b' * 64),
          ],
        ),
      ),
      discardAudio: (_) async {},
      saveBookAudioPosition: (context, wire, current) async {
        final saved = await positions.saveAudio(
          await context.toBook(wire),
          expectedRevision: revision,
          isCurrent: current,
        );
        if (saved != null) revision = saved.revision;
      },
    );
    addTearDown(owner.close);
    final reader = BookReaderController(
      book: Book(key: key, title: 'Livre', authors: [], languages: ['fr']),
      content: f.content,
      positions: positions,
      playback: owner,
    );
    await reader.initialize();
    await reader.listenHere();
    expect(await positions.read(key, ReadingMode.audio), isNull);
    await reader.go(
      BookLocator(key: key, chapterId: 'c0', blockId: 'b3', offsetUtf16: 0),
    );
    speech.complete(speech.requests.first.requestId);
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(reader.visible!.blockId, 'b3');
    expect(
      (await positions.read(key, ReadingMode.audio))!.locator.blockId,
      'b0',
    );
    await reader.showHeard();
    await reader.flush();
    expect(reader.visible!.blockId, 'b0');
    await owner.stop();
    final english = BookReaderController(
      book: Book(key: key, title: 'English', authors: [], languages: ['en']),
      content: f.content,
      playback: owner,
    );
    await english.initialize();
    final requests = speech.requests.length;
    await english.listenHere();
    expect(speech.requests.length, requests);
    expect(english.narrationMessage, contains('français'));
    await english.close();
    await reader.close();
  });
}
