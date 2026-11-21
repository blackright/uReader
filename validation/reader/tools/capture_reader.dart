// Developer-only synthetic captures. Uses installed fonts without bundling them.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/features/book_reader/book_reader_controller.dart';
import 'package:prototype/features/book_reader/book_reader_screen.dart';
import 'package:prototype/infrastructure/database/book_preferences_repository.dart';
import 'package:prototype/infrastructure/database/experience_preferences_repository.dart';
import 'package:prototype/infrastructure/database/page_index_repository.dart';

import '../../../test/features/book_reader/reader_fixture.dart';
import '../../../test/features/book_reader/paged_reader_screen_test.dart'
    show settleReader, runReaderOperation;

void main() {
  testWidgets('capture synthetic reader references', (tester) async {
    const stage = String.fromEnvironment(
      'VISUAL_STAGE',
      defaultValue: 'before',
    );
    expect(RegExp(r'^[a-z-]+$').hasMatch(stage), isTrue);
    await tester.runAsync(() async {
      for (final entry in {
        'Roboto': 'C:/dev/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
        'MaterialIcons': 'C:/dev/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        'serif': 'C:/Windows/Fonts/georgia.ttf',
      }.entries) {
        final file = File(entry.value);
        if (await file.exists()) {
          await (FontLoader(entry.key)..addFont(
                file.readAsBytes().then((b) => ByteData.sublistView(b)),
              ))
              .load();
        }
      }
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = ReaderFixture();
    await tester.runAsync(f.open);
    final key = (await tester.runAsync(
      () => f.book(
        'visual-demo',
        blocks: 8,
        text: 'Chaque matin, Léa ouvre la petite porte du jardin. La lumière traverse les feuilles et dessine sur le chemin des ombres légères. Elle prend le temps de lire, puis reprend sa promenade. ',
      ),
    ))!;
    for (final theme in ReaderTheme.values) {
      final prefs = (await tester.runAsync(
        () async => BookPreferencesRepository(f.db),
      ))!;
      await tester.runAsync(() => prefs.save(ReaderPreferences(theme: theme)));
      final reader = (await tester.runAsync(
        () async => BookReaderController(
          book: Book(
            key: key,
            title: 'Les heures tranquilles',
            authors: ['Camille Martin'],
            languages: ['fr'],
          ),
          content: f.content,
          preferenceStore: prefs,
          experienceStore: ExperiencePreferencesRepository(f.db, reader: prefs),
          pageIndexStore: PageIndexRepository(f.db),
        ),
      ))!;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: BookReaderScreen(
              book: reader.book,
              content: f.content,
              controller: reader,
            ),
          ),
        ),
      );
      await settleReader(tester, reader);
      Future<void> save(String screen) async {
        await tester.pump(const Duration(milliseconds: 100));
        final image = (await tester.runAsync(
          () =>
              (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2),
        ))!;
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.png),
        );
        await tester.runAsync(() async {
          final out = File(
            'validation/reader/reports/visual/$screen-$stage-${theme.name}.png',
          );
          await out.parent.create(recursive: true);
          await out.writeAsBytes(bytes!.buffer.asUint8List());
        });
        image.dispose();
      }

      await save('reader');
      if (stage != 'before') {
        await tester.tap(find.byTooltip('Réglages de lecture'));
        await tester.pumpAndSettle();
        await save('settings');
        await tester.ensureVisible(find.text('Annuler'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Sommaire'));
        await tester.pumpAndSettle();
        await save('chapters');
        Navigator.of(tester.element(find.text('Sommaire').last)).pop();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
      await runReaderOperation(tester, reader.close);
    }
    await tester.runAsync(f.close);
  });
}
