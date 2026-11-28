import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app/dependencies.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/features/demo_reader/corpus_repository.dart';
import 'package:prototype/main.dart';
import 'package:prototype/features/welcome/welcome_screen.dart';

Future<void> settleStartup(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (find.text('Ouverture de votre bibliothèque').evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

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
    await WelcomeStore(dependencies.files.root).complete();
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
    await tester.runAsync(() => WelcomeStore(fallback.files.root).complete());
    expect(fallback.models, isNull);
    await tester.pumpWidget(MainApp(createDependencies: () async => fallback));
    await settleStartup(tester);
    expect(find.text('Bibliothèque'), findsOneWidget);
    await tester.tap(find.text('Voix'));
    await settleStartup(tester);
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
    await settleStartup(tester);
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
    await settleStartup(tester);
    await tester.tap(find.text('Voix'));
    await settleStartup(tester);
    expect(find.text('Préparation de la voix'), findsOneWidget);
    expect(find.text('Démo'), findsNothing);
    expect(find.text('Bilan'), findsNothing);
    expect(find.byType(NavigationDestination), findsNWidgets(2));
    await tester.tap(find.text('Livres'));
    await settleStartup(tester);
    expect(find.text('Bibliothèque'), findsOneWidget);
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
    await settleStartup(tester);
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
    await settleStartup(tester);
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
      await settleStartup(tester);
      expect(
        find.text(const AppError(ErrorCode.unsupportedSchema).message),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
