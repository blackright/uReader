import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/features/listening/content_source_adapter.dart';
import 'package:prototype/features/listening/playback_coordinator.dart';

import 'epub_management_harness.dart';
import 'feasibility_bootstrap.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'US4 real voice: remove active owner, then another book without stopping playback',
    (tester) async {
      await waitForNative(tester);
      final h = EpubManagementHarness();
      await h.open(audio: true);
      final a = await h.importAt(0),
          b = await h.importAt(1),
          c = await h.importAt(2);
      final originalHashes = <String, String>{};
      for (final book in [a, b, c]) {
        originalHashes[book.key.id] = sha256
            .convert(
              await File('${h.root.path}/originals/${book.key.id}.epub')
                  .readAsBytes(),
            )
            .toString();
      }
      final owner = h.playback!;
      final played = <String>[];
      Completer<void>? started;
      void observe() {
        if (owner.state == PlaybackState.playing &&
            owner.playedLocator != null &&
            owner.bookKey != null) {
          played.add(owner.bookKey!.id);
          if (started != null && !started!.isCompleted) started!.complete();
        }
      }

      owner.addListener(observe);
      Future<void> play(Book book) async {
        started = Completer<void>();
        final block = (await h.content.window(book.key, 1)).blocks.firstWhere(
          (b) => b.speechEligible && b.text.trim().isNotEmpty,
        );
        await owner.playBook(
          BookSpeechContext(book.key, h.content),
          from: BookLocator(
            key: book.key,
            chapterId: block.chapterId,
            blockId: block.id,
            offsetUtf16: 0,
          ),
        );
        await started!.future.timeout(const Duration(seconds: 90));
      }

      try {
        await play(a);
        expect(await h.removal.remove(a.key, confirmed: true), true);
        final afterDelete = played.length;
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(owner.state, PlaybackState.stopped);
        expect(owner.bookKey, isNull);
        expect(played.skip(afterDelete).where((id) => id == a.key.id), isEmpty);
        await play(b);
        expect(owner.positionError, isNull);
        expect(await h.removal.remove(c.key, confirmed: true), true);
        expect(owner.bookKey, b.key);
        expect(
          owner.state,
          anyOf(PlaybackState.playing, PlaybackState.preparing),
        );
        expect(owner.error, isNull);
        await owner.stop();
        expect((await h.books.readyPage()).single.key, b.key);
        for (final entry in originalHashes.entries) {
          expect(
            sha256
                .convert(
                  await File('${h.root.path}/originals/${entry.key}.epub')
                      .readAsBytes(),
                )
                .toString(),
            entry.value,
          );
        }
        binding.reportData = {
          'removalAudio': {
            'activeBookRemoved': true,
            'lateStartsAfterDeletion': 0,
            'otherBookContinued': true,
            'remainingBook': b.key.id,
            'originalsUnchanged': 3,
            'session': 'single real Pocket TTS/player/system handler',
            'acousticSilenceMeasured': false,
            'productDatabaseOpened': false,
          },
        };
      } finally {
        owner.removeListener(observe);
        await h.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
