import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/features/model_setup/model_installer.dart';
import 'package:prototype/features/model_setup/model_removal_service.dart';
import 'package:prototype/features/model_setup/model_setup_screen.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/files/private_file_store.dart';

import 'model_installer_test.dart' show fixtureCatalog, MemoryBundleSource;

void main() {
  late Directory root;
  late PrototypeDatabase db;
  late ModelInstaller installer;
  late ModelRemovalService removal;
  late MemoryBundleSource source;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ureader-setup-ui-');
    final files = await PrivateFileStore.open(root);
    db = PrototypeDatabase(NativeDatabase.memory());
    await db.initialize();
    source = MemoryBundleSource([1, 2, 3]);
    installer = ModelInstaller(
      catalog: fixtureCatalog([1, 2, 3]),
      files: files,
      database: db,
      source: source,
    );
    removal = ModelRemovalService(
      files: files,
      database: db,
      releaseVoice: () async {},
      resumeVoice: () {},
      gate: installer.gate,
    );
  });
  tearDown(() async {
    await installer.close();
    await db.close();
    await root.delete(recursive: true);
  });
  testWidgets('installed voice opens explicit preview without starting audio', (
    tester,
  ) async {
    await tester.runAsync(() => installer.install());
    expect(installer.state, ModelSetupState.ready);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModelSetupScreen(
            installer: installer,
            removal: removal,
            onPreview: () => opened = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(opened, isFalse);
    for (
      var i = 0;
      i < 100 && installer.state == ModelSetupState.checking;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
    }
    expect(installer.state, ModelSetupState.ready);
    await tester.scrollUntilVisible(find.text('Ouvrir la préécoute'), 200);
    await tester.tap(find.text('Ouvrir la préécoute'));
    expect(opened, isTrue);
  });
  testWidgets(
    'notices include model attribution and expose dependency licenses',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelSetupScreen(installer: installer, removal: removal),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('Licences et attribution'),
        200,
      );
      await tester.tap(find.text('Licences et attribution'));
      for (
        var i = 0;
        i < 50 && find.text('Licences des dépendances').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pumpAndSettle();
      }
      final text = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      expect(text, contains('CC BY 4.0'));
      expect(text, contains('ONNX Runtime Android 1.25.0'));
      await tester.tap(find.text('Licences des dépendances'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      expect(source.selections, 0);
      expect(tester.takeException(), isNull);
    },
  );
  for (final scale in [1.0, 2.0, 3.2]) {
    testWidgets('preparation remains accessible and explicit at scale $scale', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: ModelSetupScreen(installer: installer, removal: removal),
              ),
            ),
          ),
        );
        for (
          var i = 0;
          i < 20 && installer.state == ModelSetupState.checking;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pumpAndSettle();
        }
        expect(source.selections, 0);
        await tester.scrollUntilVisible(
          find.text('Installer depuis un dossier'),
          200,
        );
        final installButton = find.widgetWithText(
          FilledButton,
          'Installer depuis un dossier',
        );
        await tester.ensureVisible(installButton);
        await tester.pumpAndSettle();
        expect(installButton.hitTestable(), findsOneWidget);
        await tester.tap(installButton);
        await tester.pumpAndSettle();
        expect(find.text('Installer la voix française ?'), findsOneWidget);
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        expect(source.selections, 0);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}
