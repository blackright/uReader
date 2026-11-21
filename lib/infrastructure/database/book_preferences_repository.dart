import 'dart:convert';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import 'prototype_database.dart';

class BookPreferencesRepository implements ReaderPreferenceStore {
  BookPreferencesRepository(this.db);
  final PrototypeDatabase db;
  Future<void> _tail = Future.value();
  @override
  Future<ReaderPreferences> read() async {
    try {
      await _tail;
      final rows = await db
          .customSelect('SELECT * FROM book_reader_preferences')
          .get();
      double scale = 1;
      var theme = ReaderTheme.light;
      for (final r in rows) {
        if (r.read<int>('version') != 1) {
          throw const BookFailure(BookError.unsupportedContent);
        }
        final value = jsonDecode(r.read<String>('value_json'));
        switch (r.read<String>('preference_key')) {
          case 'font_scale':
            if (value is! num) {
              throw const BookFailure(BookError.invalidContent);
            }
            scale = value.toDouble();
          case 'theme':
            theme = ReaderTheme.values.byName(value as String);
        }
      }
      return ReaderPreferences(fontScale: scale, theme: theme);
    } on BookFailure {
      rethrow;
    } catch (_) {
      throw const BookFailure(BookError.storageUnavailable);
    }
  }

  @override
  Future<void> save(ReaderPreferences preferences) =>
      writeCombined(preferences: preferences);

  /// All reader/experience writes share this queue and one transaction.
  Future<void> writeCombined({
    ReaderPreferences? preferences,
    Future<void> Function()? additional,
  }) {
    final task = _tail.then((_) async {
      try {
        await db.transaction(() async {
          if (preferences != null) {
            for (final entry in {
              'font_scale': preferences.fontScale,
              'theme': preferences.theme.name,
            }.entries) {
              await db.customStatement(
                'INSERT INTO book_reader_preferences VALUES (?,?,1) ON CONFLICT(preference_key) DO UPDATE SET value_json=excluded.value_json,version=1',
                [entry.key, jsonEncode(entry.value)],
              );
            }
          }
          await additional?.call();
        });
      } catch (_) {
        throw const BookFailure(BookError.storageUnavailable);
      }
    });
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<void> flush() => _tail;
}
