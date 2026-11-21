import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/features/audio_player/player_presenter.dart';
import 'package:prototype/features/audio_player/full_player_screen.dart';
import 'package:prototype/features/audio_player/mini_player.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/reader_experience.dart';
import 'package:prototype/infrastructure/database/experience_preferences_repository.dart';

import '../book_reader/paged_reader_screen_test.dart' show runReaderOperation;
import 'player_fixture.dart';

import 'package:prototype/features/audio_player/content_seek_sheet.dart';
import 'package:prototype/features/book_reader/paragraph_actions.dart';

import '../book_reader/paged_reader_screen_test.dart' show waitForReaderControl;

void main() {
  for (final scale in [1.0, 3.2]) {
    testWidgets(
      'player surfaces and persisted presentation at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = PlayerFixture();
        await tester.runAsync(f.open);
        final key = (await tester.runAsync(() => f.book('surfaces')))!;
        final presenter = (await tester.runAsync(
          () async => PlayerPresenter(
            owner: f.owner,
            source: f.content,
            preferences: ExperiencePreferencesRepository(f.db),
            lookup: (k) async => PlayerBook(
              Book(
                key: k,
                title: 'Le jardin des heures',
                authors: ['Camille Martin'],
                languages: ['fr'],
              ),
            ),
          ),
        ))!;
        await tester.runAsync(presenter.initialize);
        await tester.runAsync(
          () => f.owner.playFromParagraph(f.context(key), f.at(key, 0)),
        );
        await tester.runAsync(f.owner.pause);
        await tester.runAsync(presenter.refresh);
        final generation = f.owner.sessionGeneration;
        await tester.pumpWidget(
          MaterialApp(
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: FullPlayerScreen(
              presenter: presenter,
              onShowHeard: (_, _) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Le jardin des heures'), findsWidgets);
        expect(find.text('Lecture en pause'), findsOneWidget);
        expect(find.textContaining('min'), findsNothing);
        await tester.ensureVisible(find.text('Simplifié'));
        await tester.tap(find.text('Simplifié'));
        for (var i = 0; i < 30; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        expect(presenter.presentation, AudioPresentation.simple);
        expect(f.owner.sessionGeneration, generation);
        expect(find.text('Paragraphe suivant'), findsOneWidget);
        await tester.pumpWidget(
          MaterialApp(
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: MiniPlayer(presenter: presenter, onOpen: () {}),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Le jardin des heures'), findsOneWidget);
        await runReaderOperation(tester, f.owner.stop);
        await tester.pump();
        expect(find.text('Le jardin des heures'), findsNothing);
        final stored = (await tester.runAsync(
          () => presenter.preferences.read(),
        ))!;
        expect(stored.presentation, AudioPresentation.simple);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        presenter.dispose();
        await tester.runAsync(f.close);
      },
    );
  }
  testWidgets('preview selection and cancellation never seek or synthesize', (
    tester,
  ) async {
    final f = PlayerFixture();
    await tester.runAsync(f.open);
    final key = (await tester.runAsync(() => f.book('cancel-target')))!;
    BookLocator? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                chosen = await showModalBottomSheet<BookLocator>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => ContentSeekSheet(
                    book: Book(
                      key: key,
                      title: 'Livre de validation',
                      authors: [],
                      languages: ['fr'],
                    ),
                    source: f.content,
                  ),
                );
              },
              child: const Text('Choisir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choisir'));
    for (var i = 0; i < 100 && find.byType(ListTile).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(ListTile).first);
    await tester.tap(find.byType(ListTile).first);
    for (
      var i = 0;
      i < 100 &&
          find.text('Cible retenue · début du paragraphe').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    expect(find.text('Cible retenue · début du paragraphe'), findsOneWidget);
    await tester.ensureVisible(find.text('Annuler'));
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(chosen, isNull);
    expect(f.speech.requests, isEmpty);
    expect(f.player.opens, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(f.close);
  });
  testWidgets(
    'voice failure stays visible and reopening a player never starts speech',
    (tester) async {
      final f = PlayerFixture();
      await tester.runAsync(f.open);
      final key = (await tester.runAsync(() => f.book('voice-failure')))!;
      final p = (await tester.runAsync(
        () async => PlayerPresenter(
          owner: f.owner,
          source: f.content,
          preferences: ExperiencePreferencesRepository(f.db),
          lookup: (k) async => PlayerBook(
            Book(
              key: k,
              title: 'Livre sans voix disponible',
              authors: [],
              languages: ['fr'],
            ),
          ),
        ),
      ))!;
      await tester.runAsync(p.initialize);
      await tester.runAsync(
        () => f.owner.playFromParagraph(f.context(key), f.at(key, 0)),
      );
      f.speech.fail(f.speech.requests.last.requestId);
      await tester.runAsync(f.settle);
      await tester.runAsync(p.refresh);
      final requests = f.speech.requests.length;
      await tester.pumpWidget(
        MaterialApp(
          home: FullPlayerScreen(presenter: p, onShowHeard: (_, _) async {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(f.owner.error!.message), findsOneWidget);
      expect(f.speech.requests.length, requests);
      expect(f.player.opens, 0);
      expect(p.miniVisible, isFalse);
      await tester.pumpWidget(const SizedBox());
      p.dispose();
      await tester.runAsync(f.close);
    },
  );
  testWidgets(
    'paragraph preview without narration explains the disabled action',
    (tester) async {
      final f = PlayerFixture();
      await tester.runAsync(f.open);
      final key = (await tester.runAsync(() => f.book('no-narration')))!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => ParagraphActions.show(
                  ctx,
                  book: Book(
                    key: key,
                    title: 'Lecture visuelle',
                    authors: [],
                    languages: ['en'],
                  ),
                  source: f.content,
                  at: f.at(key, 0),
                  canListen: false,
                ),
                child: const Text('Paragraphe'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Paragraphe'));
      await waitForReaderControl(tester, find.text('Paragraphe sélectionné'));
      final action = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Écouter à partir d’ici'),
      );
      expect(action.onPressed, isNull);
      expect(find.textContaining('Le texte reste consultable'), findsOneWidget);
      expect(f.speech.requests, isEmpty);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(f.close);
    },
  );
}
