import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app/dependencies.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/features/demo_reader/corpus_repository.dart';
import 'package:prototype/main.dart';

void main() {
  late Directory directory;
  late AppDependencies dependencies;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ureader-app-');
    dependencies = await AppDependencies.open(
      directory: directory,
      executor: NativeDatabase.memory(),
      corpus: CorpusRepository(
        read: () async => File('assets/corpus/fr_demo.json').readAsStringSync(),
      ),
    );
  });
  tearDown(() async {
    await dependencies.dispose();
    await directory.delete(recursive: true);
  });

  testWidgets('Un catalogue vocal invalide laisse les textes consultables', (
    tester,
  ) async {
    final fallback = (await tester.runAsync(
      () => AppDependencies.open(
        directory: Directory('${directory.path}/invalid-catalog'),
        executor: NativeDatabase.memory(),
        corpus: dependencies.corpus,
        loadSpeechManifest: () async => ByteData(0),
      ),
    ))!;
    addTearDown(fallback.dispose);
    expect(fallback.models, isNull);
    await tester.pumpWidget(MainApp(createDependencies: () async => fallback));
    await tester.pumpAndSettle();
    expect(find.text('Bibliothèque'), findsOneWidget);
    await tester.tap(find.text('Démo'));
    await tester.pumpAndSettle();
    expect(find.text('Choisir un texte'), findsOneWidget);
    await tester.tap(find.text('Voix'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Le catalogue vocal est indisponible. Les textes restent consultables.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Le démarrage reste français, sans fonction vocale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MainApp(createDependencies: () async => dependencies),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bibliothèque'), findsOneWidget);
    expect(find.text('Importer un EPUB'), findsOneWidget);
    expect(find.textContaining('Votre bibliothèque est vide'), findsOneWidget);
    expect(find.text('Choisir un texte'), findsNothing);
    expect(
      Localizations.localeOf(tester.element(find.byType(NavigationBar))),
      const Locale('fr'),
    );
    expect((await dependencies.speech.capabilities()).voices, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Navigation minimale et retour sans démarrer un moteur', (
    tester,
  ) async {
    await tester.pumpWidget(
      MainApp(createDependencies: () async => dependencies),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voix'));
    await tester.pumpAndSettle();
    expect(find.text('Préparation de la voix'), findsOneWidget);
    await tester.tap(find.text('Bilan'));
    await tester.pumpAndSettle();
    expect(find.text('Bilan de faisabilité'), findsOneWidget);
    expect(find.text('Faisabilité partielle'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Démo'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choisir un texte'), findsOneWidget);
    expect(await dependencies.database.pendingOperations(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Grand texte : pas de débordement dans la navigation minimale', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MainApp(createDependencies: () async => dependencies),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Un échec de stockage affiche une erreur française expurgée', (
    tester,
  ) async {
    await tester.pumpWidget(
      MainApp(
        createDependencies: () async {
          throw const AppError(ErrorCode.storageUnavailable);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(const AppError(ErrorCode.storageUnavailable).message),
      findsOneWidget,
    );
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Un schéma ambigu affiche son erreur spécifique sans détails SQL',
    (tester) async {
      await tester.pumpWidget(
        MainApp(
          createDependencies: () async {
            throw const AppError(ErrorCode.unsupportedSchema);
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(const AppError(ErrorCode.unsupportedSchema).message),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
