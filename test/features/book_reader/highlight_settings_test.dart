import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/domain/reader_experience.dart';
import 'package:prototype/features/book_reader/reading_settings_sheet.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'highlight choice applies and cancel preserves preference, dark=$dark',
      (tester) async {
        ReadingSettings? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await showModalBottomSheet<ReadingSettings>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => ReadingSettingsSheet(
                        preferences: ReaderPreferences(
                          theme: dark ? ReaderTheme.dark : ReaderTheme.light,
                        ),
                        experience: ExperiencePreferences(
                          highlightColor: HighlightColor.green,
                        ),
                        extended: true,
                      ),
                    );
                  },
                  child: const Text('Réglages'),
                ),
              ),
            ),
          ),
        );
        Future<void> choose(String action) async {
          await tester.tap(find.text('Réglages'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Bleu'));
          await tester.tap(find.text('Bleu'));
          await tester.pump();
          await tester.ensureVisible(find.text(action));
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();
        }

        await choose('Appliquer');
        expect(result!.experience.highlightColor, HighlightColor.blue);
        expect(result!.experience.followEnabled, isTrue);
        await choose('Annuler');
        expect(result, isNull);
      },
    );
  }
}
