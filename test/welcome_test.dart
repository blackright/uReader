import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app/reader_theme.dart';
import 'package:prototype/features/welcome/welcome_screen.dart';

void main() {
  test('welcome completion persists across store instances', () async {
    final root = await Directory.systemTemp.createTemp('welcome-');
    try {
      expect(await WelcomeStore(root).completed(), isFalse);
      await WelcomeStore(root).complete();
      expect(await WelcomeStore(root).completed(), isTrue);
    } finally {
      await root.delete(recursive: true);
    }
  });
  for (final scale in [1.0, 3.2]) {
    testWidgets('complete three steps or skip, scale=$scale', (tester) async {
      var finishes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ReaderVisualTheme.theme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: WelcomeScreen(
            onFinish: () async {
              finishes++;
            },
          ),
        ),
      );
      for (var step = 0; step < 2; step++) {
        await tester.ensureVisible(find.text('Continuer'));
        await tester.tap(find.text('Continuer'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.text('Ouvrir ma bibliothèque'));
      await tester.tap(find.text('Ouvrir ma bibliothèque'));
      await tester.pumpAndSettle();
      expect(finishes, 1);
      await tester.ensureVisible(find.text('Passer'));
      await tester.tap(find.text('Passer'));
      await tester.pumpAndSettle();
      expect(finishes, 2);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed save exposes retry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeScreen(
          onFinish: () async {
            throw const FileSystemException();
          },
        ),
      ),
    );
    await tester.tap(find.text('Passer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('n’a pas pu être enregistré'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Passer'))
          .onPressed,
      isNotNull,
    );
  });
}
