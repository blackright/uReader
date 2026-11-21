import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';
import 'package:prototype/features/demo_reader/corpus_repository.dart';
import 'package:prototype/features/demo_reader/reader_controller.dart';
import 'package:prototype/infrastructure/database/position_repository.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';

import '../listening/playback_coordinator_test.dart'
    show RecordingSpeech, RecordingPlayer;

void main() {
  late PrototypeDatabase db;
  late PositionRepository positions;
  late ReaderController reader;
  setUp(() async {
    db = PrototypeDatabase(NativeDatabase.memory());
    await db.initialize();
    positions = PositionRepository(
      db,
      latestVisual: db.readLatestVisualPosition,
    );
    reader = ReaderController(
      positions: positions,
      corpus: CorpusRepository(
        read: () => File('assets/corpus/fr_demo.json').readAsString(),
      ),
    );
  });
  tearDown(() async {
    reader.dispose();
    await positions.flush();
    await db.close();
  });

  test(
    'consulting elsewhere and showing spoken passage never seek audio',
    () async {
      final speech = RecordingSpeech();
      final player = RecordingPlayer();
      final owner = PlaybackCoordinator(
        speech: speech,
        player: player,
        segmenter: SpeechSegmenter((s) async => s.split(' ').length),
        discardAudio: (_) async {},
        prepareEngine: () => speech.loadBundle(
          BundleDescriptor(
            id: 'fr-official-aligned',
            version: 'v1',
            manifestDigest: 'a' * 64,
            files: [
              BundleFile(relativePath: 'test', byteSize: 1, sha256: 'b' * 64),
            ],
          ),
        ),
        saveAudioPosition: (t, l, current) async => (await positions.save(
          t,
          l,
          ReadingMode.audio,
          isCurrent: current,
        ))?.locator,
      );
      addTearDown(owner.close);
      final controlled = ReaderController(
        corpus: reader.corpus,
        positions: positions,
        playback: owner,
      );
      addTearDown(controlled.dispose);
      final entries = await controlled.load();
      await controlled.selectText(entries.first);
      await controlled.listenHere(controlled.beginning(entries.first.text));
      speech.complete(speech.requests.first.requestId);
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(owner.state, PlaybackState.playing);
      final count = speech.requests.length;
      final opens = player.opens;
      final heard = owner.playedLocator;
      await controlled.selectText(entries[1]);
      expect(player.playing, isTrue);
      expect(owner.textId, entries.first.text.id);
      await controlled.showSpokenPassage();
      expect(controlled.visualLocator, same(heard));
      expect(player.opens, opens);
      expect(speech.requests.length, count);
    },
  );

  test('restore distinct durable locators without starting speech', () async {
    final entries = await reader.load();
    final text = entries.first.text;
    final visual = Locator(
      textId: text.id,
      corpusVersion: 1,
      passageId: text.passages.last.id,
      offsetUtf16: 0,
    );
    final audio = reader.beginning(text);
    await positions.save(text, visual, ReadingMode.visual);
    await positions.save(text, audio, ReadingMode.audio);
    final restored = ReaderController(
      corpus: reader.corpus,
      positions: positions,
    );
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.selected!.text.id, text.id);
    expect(restored.visualLocator!.passageId, visual.passageId);
    expect(
      (await positions.read(text, ReadingMode.audio))!.locator.passageId,
      audio.passageId,
    );
    expect(restored.playback, isNull);
    await restored.selectPassage(audio);
    expect((await positions.read(text, ReadingMode.audio))!.revision, 1);
  });

  test(
    'incompatible visual position falls back explicitly without deleting audio',
    () async {
      final entries = await reader.load();
      final entry = entries.first;
      await db.customStatement(
        'INSERT INTO positions VALUES (?, ?, 2, ?, 0, 1, 1)',
        [entry.text.id, 'visual', entry.text.passages.first.id],
      );
      await reader.selectText(entry, save: false);
      expect(reader.visualLocator!.corpusVersion, 1);
      expect(reader.warning, isNotNull);
      expect(
        (await db.readPosition(
          entry.text.id,
          ReadingMode.visual,
        ))!.locator.corpusVersion,
        2,
      );
    },
  );
}
