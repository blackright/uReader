import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/domain/app_error.dart';

import '../../fixtures/reader_schema_v2.dart';
import 'book_migration_test.dart' show historicalSchema;

void main() {
  for (final version in [0, 1, 2]) {
    test('reader migrates exact v$version without replacing legacy data', () async {
      final dir = await Directory.systemTemp.createTemp('reader-migration-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/db.sqlite');
      final db = PrototypeDatabase(
        NativeDatabase(
          file,
          setup: (raw) {
            for (final sql in historicalSchema) {
              raw.execute(sql);
            }
            if (version == 2) {
              for (final sql in FrozenBookSchemaV2.statements) {
                raw.execute(sql);
              }
            }
            raw.execute(
              "INSERT INTO positions VALUES('demo','audio',1,'p0',0,7,1)",
            );
            raw.execute(
              "INSERT INTO installed_bundles VALUES('fr','1','${'a' * 64}','models/fr/1','ready',1)",
            );
            raw.execute('PRAGMA user_version=$version');
          },
        ),
      );
      try {
        await db.initialize();
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          3,
        );
        expect(
          (await db.customSelect('SELECT revision FROM positions').getSingle())
              .read<int>('revision'),
          7,
        );
        expect(
          (await db
                  .customSelect('SELECT manifest_digest FROM installed_bundles')
                  .getSingle())
              .read<String>('manifest_digest'),
          'a' * 64,
        );
        expect(
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE name='book_bookmarks'",
                  )
                  .get())
              .length,
          1,
        );
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await db.close();
      }
      final reopened = PrototypeDatabase(NativeDatabase(file));
      try {
        await reopened.initialize();
      } finally {
        await reopened.close();
      }
    });
  }
  test('v2 full storage rolls back all v3 DDL and permits retry', () async {
    final dir = await Directory.systemTemp.createTemp('reader-full-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final db = PrototypeDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          for (final sql in [
            ...historicalSchema,
            ...FrozenBookSchemaV2.statements,
          ]) {
            raw.execute(sql);
          }
          raw.execute(
            "INSERT INTO positions VALUES('demo','visual',1,'p0',0,2,1)",
          );
          raw.execute('PRAGMA user_version=2');
          final pages =
              raw.select('PRAGMA page_count').single['page_count'] as int;
          raw.execute('PRAGMA max_page_count=${pages + 1}');
        },
      ),
    );
    try {
      await expectLater(
        db.initialize(),
        throwsA(
          isA<SqliteException>().having((e) => e.resultCode, 'SQLITE_FULL', 13),
        ),
      );
    } finally {
      await db.close();
    }
    final retry = PrototypeDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          expect(raw.select('PRAGMA user_version').single['user_version'], 2);
          expect(
            raw.select(
              "SELECT name FROM sqlite_master WHERE name='book_bookmarks'",
            ),
            isEmpty,
          );
          expect(
            raw.select('SELECT revision FROM positions').single['revision'],
            2,
          );
          raw.execute('PRAGMA max_page_count=1073741823');
        },
      ),
    );
    try {
      await retry.initialize();
    } finally {
      await retry.close();
    }
  });
  test('unknown v2 SQL is refused, not repaired', () async {
    final db = PrototypeDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          for (final sql in [
            ...historicalSchema,
            ...FrozenBookSchemaV2.statements,
          ]) {
            raw.execute(sql);
          }
          raw.execute('ALTER TABLE books ADD COLUMN foreign_data TEXT');
          raw.execute('PRAGMA user_version=2');
        },
      ),
    );
    addTearDown(db.close);
    await expectLater(db.initialize(), throwsA(isA<AppError>()));
  });
}
