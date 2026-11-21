import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/storage.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';
import 'package:prototype/features/listening/content_source_adapter.dart';
import 'package:prototype/features/listening/speech_segmenter.dart';

import '../book_reader/reader_fixture.dart';
import '../listening/playback_coordinator_test.dart'
    show RecordingSpeech, RecordingPlayer;

class PlayerFixture extends ReaderFixture {
  final speech = RecordingSpeech(), player = RecordingPlayer();
  late final owner = PlaybackCoordinator(
    speech: speech,
    player: player,
    segmenter: SpeechSegmenter((s) async => 1),
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
  );
  BookSpeechContext context(ContentKey key) => BookSpeechContext(key, content);
  BookLocator at(ContentKey key, int i, {String? id, int offset = 0}) =>
      BookLocator(
        key: key,
        chapterId: i < 2 ? 'c0' : 'c1',
        blockId: id ?? 'b$i',
        offsetUtf16: offset,
      );
  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> close() async {
    await owner.close();
    await super.close();
  }
}
