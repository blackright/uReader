// Synthetic visual references only. Fake transport is not an acoustic validation.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app/reader_theme.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/reader_experience.dart';
import 'package:prototype/features/audio_player/player_presenter.dart';
import 'package:prototype/features/audio_player/full_player_screen.dart';
import 'package:prototype/features/audio_player/mini_player.dart';
import 'package:prototype/features/audio_player/content_seek_sheet.dart';
import 'package:prototype/infrastructure/database/experience_preferences_repository.dart';

import '../../../test/features/audio_player/player_fixture.dart';

void main() {
  testWidgets('capture implemented player on synthetic content', (
    tester,
  ) async {
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
    final f = PlayerFixture();
    await tester.runAsync(f.open);
    final key = (await tester.runAsync(
      () => f.book(
        'visual-player',
        blocks: 8,
        text: 'Chaque matin, Léa ouvre la petite porte du jardin. La lumière traverse les feuilles.',
      ),
    ))!;
    final p = (await tester.runAsync(
      () async => PlayerPresenter(
        owner: f.owner,
        source: f.content,
        preferences: ExperiencePreferencesRepository(f.db),
        lookup: (k) async => PlayerBook(
          Book(
            key: k,
            title: 'Les heures tranquilles',
            authors: ['Camille Martin'],
            languages: ['fr'],
          ),
        ),
      ),
    ))!;
    await tester.runAsync(p.initialize);
    await tester.runAsync(
      () => f.owner.playFromParagraph(f.context(key), f.at(key, 4)),
    );
    f.speech.complete(f.speech.requests.first.requestId);
    await tester.runAsync(f.settle);
    await tester.runAsync(p.refresh);
    final boundary = GlobalKey();
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      Widget app(Widget home) => RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ReaderVisualTheme.theme(dark: dark),
          home: home,
        ),
      );
      Future<void> save(String name) async {
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
        await tester.runAsync(
          () =>
              File('validation/reader/reports/visual/$name-phase2-$theme.png')
                  .writeAsBytes(bytes!.buffer.asUint8List()),
        );
        image.dispose();
      }

      await tester.runAsync(() => p.changePresentation(AudioPresentation.full));
      await tester.pumpWidget(
        app(FullPlayerScreen(presenter: p, onShowHeard: (_, _) async {})),
      );
      await tester.pumpAndSettle();
      await save('full-player');
      await tester.ensureVisible(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      await save('player-controls');
      await tester.runAsync(
        () => p.changePresentation(AudioPresentation.simple),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, 1000),
      );
      await tester.pumpAndSettle();
      await save('simple-player');
      await tester.pumpWidget(
        app(
          Scaffold(
            appBar: AppBar(title: const Text('Bibliothèque')),
            body: const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Vos livres, à portée de main.'),
            ),
            bottomNavigationBar: MiniPlayer(presenter: p, onOpen: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await save('mini-player');
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ContentSeekSheet(
              book: p.book!,
              source: f.content,
              initial: p.target,
            ),
          ),
        ),
      );
      for (
        var i = 0;
        i < 100 && find.byType(ListTile).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      await save('content-target');
    }
    await tester.pumpWidget(const SizedBox());
    p.dispose();
    await tester.runAsync(f.close);
  });
}
