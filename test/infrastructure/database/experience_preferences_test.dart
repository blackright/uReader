import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/books.dart';
import 'package:prototype/domain/book_reader.dart';
import 'package:prototype/domain/reader_experience.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/database/experience_preferences_repository.dart';

void main() {
  late PrototypeDatabase db;
  late ExperiencePreferencesRepository store;
  setUp(() async {
    db = PrototypeDatabase(NativeDatabase.memory());
    await db.initialize();
    store = ExperiencePreferencesRepository(db);
  });
  tearDown(() async {
    await store.flush();
    await db.close();
  });
  test('defaults and combined save keep legacy values authoritative', () async {
    expect((await store.read()).mode, ReaderMode.paged);
    await store.save(
      ExperiencePreferences(
        mode: ReaderMode.scroll,
        lineHeight: 1.8,
        margins: 28,
        followEnabled: false,
        presentation: AudioPresentation.simple,
      ),
      reader: ReaderPreferences(fontScale: 1.5, theme: ReaderTheme.dark),
    );
    final value = await store.read();
    expect(value.mode, ReaderMode.scroll);
    expect(value.followEnabled, false);
    expect((await store.readReader()).theme, ReaderTheme.dark);
    expect(
      (await db.customSelect('SELECT * FROM book_reader_preferences').get())
          .length,
      2,
    );
  });
  test('late experience failure rolls back legacy part too', () async {
    await db.customStatement(
      "CREATE TRIGGER reject_experience BEFORE INSERT ON experience_preferences BEGIN SELECT RAISE(ABORT,'test'); END",
    );
    await expectLater(
      store.save(
        ExperiencePreferences(mode: ReaderMode.scroll),
        reader: ReaderPreferences(fontScale: 1.7),
      ),
      throwsA(isA<BookFailure>()),
    );
    expect((await store.readReader()).fontScale, 1);
    expect((await store.read()).mode, ReaderMode.paged);
  });
  test('unknown versions and invalid values are not silently reset', () async {
    await db.customStatement(
      "INSERT INTO experience_preferences VALUES('reader_mode','\"scroll\"',99)",
    );
    await expectLater(store.read(), throwsA(isA<BookFailure>()));
    expect(
      () => ExperiencePreferences(lineHeight: double.nan),
      throwsA(isA<BookFailure>()),
    );
  });
  test('stored JSON null is corrupt, not an absent preference', () async {
    await db.customStatement(
      "INSERT INTO experience_preferences VALUES('reader_mode','null',1)",
    );
    await expectLater(store.read(), throwsA(isA<BookFailure>()));
    expect(
      (await db
              .customSelect('SELECT value_json FROM experience_preferences')
              .getSingle())
          .read<String>('value_json'),
      'null',
    );
  });
}
