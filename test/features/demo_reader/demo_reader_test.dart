import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app/dependencies.dart';
import 'package:prototype/main.dart';
import 'package:prototype/features/demo_reader/corpus_repository.dart';
import 'package:prototype/features/demo_reader/demo_reader_screen.dart';

Future<void> settleSelection(WidgetTester tester, AppDependencies deps) async {
  var done = false;
  Object? failure;
  deps.reader.waitForSelection().then(
    (_) {
      done = true;
    },
    onError: (Object error) {
      failure = error;
      done = true;
    },
  );
  for (var i = 0; i < 200 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  expect(failure, isNull);
  expect(done, isTrue, reason: 'Selection and durable visual save must settle');
}

void main() {
  late Directory directory;
  late AppDependencies deps;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ureader-reader-');
    deps = await AppDependencies.open(
      directory: directory,
      executor: NativeDatabase.memory(),
      corpus: CorpusRepository(
        read: () async => File('assets/corpus/fr_demo.json').readAsStringSync(),
      ),
    );
  });
  tearDown(() async {
    await deps.dispose();
    await directory.delete(recursive: true);
  });
  testWidgets('Le corpus reste consultable sans moteur ni preuve G0', (
    tester,
  ) async {
    await tester.pumpWidget(MainApp(createDependencies: () async => deps));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Démo'));
    await tester.pumpAndSettle();
    expect(find.text('Choisir un texte'), findsOneWidget);
    expect(find.text('Le jardin du matin'), findsOneWidget);
    expect(find.textContaining('Écoute indisponible'), findsOneWidget);
    expect((await deps.speech.capabilities()).voices, isEmpty);
    await tester.tap(find.text('Le jardin du matin'));
    await settleSelection(tester, deps);
    await tester.pumpAndSettle();
    expect(find.textContaining('Chaque matin, Léa'), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Tous les textes'),
      -300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    await tester.tap(find.text('Tous les textes'));
    await settleSelection(tester, deps);
    await tester.pumpAndSettle();
    expect(find.text('Choisir un texte'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Dix choix et passages restent accessibles en grande police', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 3.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MainApp(createDependencies: () async => deps));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Démo'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Une longue promenade au bord du canal'),
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    await tester.tap(find.text('Une longue promenade au bord du canal'));
    await settleSelection(tester, deps);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(SelectableText),
      300,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Les dix textes peuvent être ouverts sans voix', (tester) async {
    await tester.pumpWidget(MainApp(createDependencies: () async => deps));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Démo'));
    await tester.pumpAndSettle();
    final entries = await deps.corpus.load();
    for (final entry in entries) {
      final choice = find
          .widgetWithText(OutlinedButton, entry.text.title)
          .hitTestable();
      await tester.scrollUntilVisible(
        choice,
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 100,
      );
      await tester.tap(choice);
      await settleSelection(tester, deps);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(entry.text.passages.first.id)),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(ValueKey(entry.text.passages.first.id)),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Tous les textes'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.text('Tous les textes'),
        -300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 100,
      );
      await tester.tap(find.text('Tous les textes'));
      await settleSelection(tester, deps);
      await tester.pumpAndSettle();
      expect(find.text('Choisir un texte'), findsOneWidget);
    }
    expect((await deps.speech.capabilities()).voices, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Corpus invalide : erreur française sans détails internes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DemoReaderScreen(
            corpus: CorpusRepository(
              read: () async => throw Exception('private-path'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Le corpus ne peut pas être ouvert'),
      findsOneWidget,
    );
    expect(find.textContaining('private-path'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
