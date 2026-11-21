import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app/dependencies.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/features/demo_reader/corpus_repository.dart';
import 'package:prototype/main.dart';

void main() {
  testWidgets(
    'library restores persisted reader theme on a fresh app opening',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('ureader-library-theme-'),
      ))!;
      AppDependencies? reopened;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await reopened?.dispose();
          await directory.delete(recursive: true);
        });
      });
      reopened = await tester.runAsync(() async {
        Future<AppDependencies> open() => AppDependencies.open(
          directory: directory,
          executor: NativeDatabase(File('${directory.path}/theme-test.sqlite')),
          corpus: CorpusRepository(
            read: () => File('assets/corpus/fr_demo.json').readAsString(),
          ),
        );
        final first = await open();
        await first.bookPreferences.save(
          ReaderPreferences(theme: ReaderTheme.dark),
        );
        await first.dispose();
        return open();
      });
      expect(reopened!.initialReaderTheme, ReaderTheme.dark);
      await tester.pumpWidget(
        MainApp(createDependencies: () async => reopened!),
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(NavigationBar))).brightness,
        Brightness.dark,
      );
      expect(find.text('Bibliothèque'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
