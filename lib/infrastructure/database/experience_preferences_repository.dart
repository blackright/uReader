import 'dart:convert';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../../domain/reader_experience.dart';
import 'book_preferences_repository.dart';
import 'prototype_database.dart';

class ExperiencePreferencesRepository implements ExperiencePreferenceStore {
  ExperiencePreferencesRepository(this.db, {BookPreferencesRepository? reader})
    : reader = reader ?? BookPreferencesRepository(db);
  final PrototypeDatabase db;
  final BookPreferencesRepository reader;
  Future<ReaderPreferences> readReader() => reader.read();
  @override
  Future<ExperiencePreferences> read() async {
    await reader.flush();
    try {
      final rows = await db
          .customSelect('SELECT * FROM experience_preferences')
          .get();
      final values = <String, Object?>{};
      for (final row in rows) {
        if (row.read<int>('version') != 1) {
          throw const BookFailure(BookError.unsupportedContent);
        }
        values[row.read<String>('preference_key')] = jsonDecode(
          row.read<String>('value_json'),
        );
      }
      final mode = (values.containsKey('reader_mode')
              ? values['reader_mode']
              : 'paged'),
          height = (values.containsKey('line_height')
              ? values['line_height']
              : 1.5),
          margins = (values.containsKey('margins') ? values['margins'] : 20),
          follow = (values.containsKey('follow_enabled')
              ? values['follow_enabled']
              : true),
          display = (values.containsKey('audio_presentation')
              ? values['audio_presentation']
              : 'full');
      if (mode is! String ||
          height is! num ||
          margins is! num ||
          follow is! bool ||
          display is! String) {
        throw const BookFailure(BookError.invalidContent);
      }
      return ExperiencePreferences(
        mode: ReaderMode.values.byName(mode),
        lineHeight: height.toDouble(),
        margins: margins.toDouble(),
        followEnabled: follow,
        presentation: AudioPresentation.values.byName(display),
      );
    } on BookFailure {
      rethrow;
    } on ArgumentError {
      throw const BookFailure(BookError.invalidContent);
    } on FormatException {
      throw const BookFailure(BookError.invalidContent);
    } catch (_) {
      throw const BookFailure(BookError.storageUnavailable);
    }
  }

  @override
  Future<void> save(ExperiencePreferences value, {ReaderPreferences? reader}) =>
      this.reader.writeCombined(
        preferences: reader,
        additional: () async {
          for (final entry in <String, Object>{
            'reader_mode': value.mode.name,
            'line_height': value.lineHeight,
            'margins': value.margins,
            'follow_enabled': value.followEnabled,
            'audio_presentation': value.presentation.name,
          }.entries) {
            await db.customStatement(
              'INSERT INTO experience_preferences VALUES (?,?,1) ON CONFLICT(preference_key) DO UPDATE SET value_json=excluded.value_json,version=1',
              [entry.key, jsonEncode(entry.value)],
            );
          }
        },
      );
  @override
  Future<void> flush() => reader.flush();
}
