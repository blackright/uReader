import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/reader_experience.dart';
import 'package:prototype/features/audio_player/player_presenter.dart';
import 'package:prototype/infrastructure/database/experience_preferences_repository.dart';

import '../audio_player/player_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (var round = 0; round < 5; round++) {
    test(
      'presentation round $round preserves owner and rejects old audio',
      () async {
        final f = PlayerFixture();
        await f.open();
        addTearDown(f.close);
        final a = await f.book('race-a'), b = await f.book('race-b');
        final p = PlayerPresenter(
          owner: f.owner,
          source: f.content,
          preferences: ExperiencePreferencesRepository(f.db),
          lookup: (_) async => null,
        );
        addTearDown(p.dispose);
        await p.initialize();
        await f.owner.playFromParagraph(f.context(a), f.at(a, 0));
        final request = f.speech.requests.last;
        final generation = f.owner.sessionGeneration;
        await p.changePresentation(AudioPresentation.simple);
        await p.changePresentation(AudioPresentation.full);
        expect(f.owner.sessionGeneration, generation);
        expect(f.owner.bookKey, a);
        await f.owner.pause();
        f.speech.complete(request.requestId);
        await f.settle();
        expect(f.player.opens, 0);
        await f.owner.resume();
        await f.settle();
        expect(f.player.opens, 1);
        await f.owner.stop();
        await f.owner.playFromParagraph(f.context(b), f.at(b, 0));
        f.speech.complete(request.requestId, simulateLateResult: true);
        await f.settle();
        expect(f.owner.bookKey, b);
        expect(f.owner.playedLocator, isNull);
        expect(f.player.playing, isFalse);
      },
    );
  }
  test('late book metadata cannot replace the new session snapshot', () async {
    final f = PlayerFixture();
    await f.open();
    addTearDown(f.close);
    final a = await f.book('old-metadata'), b = await f.book('new-metadata');
    final gate = Completer<PlayerBook?>();
    final p = PlayerPresenter(
      owner: f.owner,
      source: f.content,
      preferences: ExperiencePreferencesRepository(f.db),
      lookup: (k) => k == a
          ? gate.future
          : Future.value(
              PlayerBook(
                Book(
                  key: b,
                  title: 'Nouveau livre',
                  authors: [],
                  languages: ['fr'],
                ),
              ),
            ),
    );
    addTearDown(p.dispose);
    await p.initialize();
    await f.owner.playFromParagraph(f.context(a), f.at(a, 0));
    await f.owner.playFromParagraph(f.context(b), f.at(b, 0));
    await p.refresh();
    gate.complete(
      PlayerBook(
        Book(key: a, title: 'Ancien livre', authors: [], languages: ['fr']),
      ),
    );
    await f.settle();
    expect(p.book!.key, b);
    expect(p.book!.title, 'Nouveau livre');
  });
}
