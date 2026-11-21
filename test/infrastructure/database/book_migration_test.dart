import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';

// Frozen SQL from schema v1. Never derive this fixture from the new schema.
const historicalSchema = [
  "CREATE TABLE positions ( text_id TEXT NOT NULL, mode TEXT NOT NULL CHECK(mode IN ('visual','audio')), corpus_version INTEGER NOT NULL CHECK(corpus_version > 0), passage_id TEXT NOT NULL, offset_utf16 INTEGER NOT NULL CHECK(offset_utf16 >= 0), revision INTEGER NOT NULL CHECK(revision > 0), updated_at INTEGER NOT NULL, PRIMARY KEY(text_id, mode))",
  "CREATE TABLE installed_bundles ( bundle_id TEXT NOT NULL, version TEXT NOT NULL, manifest_digest TEXT NOT NULL CHECK(length(manifest_digest) = 64), relative_directory TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('ready')), verified_at INTEGER NOT NULL, PRIMARY KEY(bundle_id, version))",
  "CREATE TABLE operations ( id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('install','delete')), bundle_id TEXT NOT NULL, bundle_version TEXT NOT NULL, manifest_digest TEXT NOT NULL CHECK(length(manifest_digest) = 64), phase TEXT NOT NULL CHECK(phase IN ('pending','published','error')), error_code TEXT, updated_at INTEGER NOT NULL)",
  'CREATE INDEX operations_phase ON operations(phase, updated_at)',
];

void main() {
  for (final version in [0, 1]) {
    test('adopts exact historical v$version and preserves positions and voice', () async {
      final dir = await Directory.systemTemp.createTemp('epub-migration-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/prototype.sqlite');
      final db = PrototypeDatabase(
        NativeDatabase(
          file,
          setup: (raw) {
            for (final sql in historicalSchema) {
              raw.execute(sql);
            }
            raw.execute(
              "INSERT INTO positions VALUES ('demo','audio',1,'p1',2,3,4)",
            );
            raw.execute(
              "INSERT INTO installed_bundles VALUES ('fr','v1','${'a' * 64}','models/fr/v1','ready',5)",
            );
            raw.execute('PRAGMA user_version = $version');
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
          (await db.customSelect('SELECT * FROM positions').getSingle())
              .read<int>('revision'),
          3,
        );
        expect(
          (await db.customSelect('SELECT * FROM installed_bundles').getSingle())
              .read<String>('manifest_digest'),
          'a' * 64,
        );
        expect(
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE name='books'",
                  )
                  .get())
              .length,
          1,
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
  test('ambiguous v1 is refused without destructive repair', () async {
    final db = PrototypeDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          for (final sql in historicalSchema) {
            raw.execute(sql);
          }
          raw.execute('ALTER TABLE positions ADD COLUMN foreign_column TEXT');
          raw.execute('PRAGMA user_version=1');
        },
      ),
    );
    addTearDown(db.close);
    await expectLater(db.initialize(), throwsA(isA<AppError>()));
  });
  test('empty database starts at v3', () async {
    final db = PrototypeDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.initialize();
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .single,
      3,
    );
  });
  test('disk-full mid-migration rolls back schema and data then reopens', () async {
    final dir = await Directory.systemTemp.createTemp('epub-rollback-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/prototype.sqlite');
    final db = PrototypeDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          for (final sql in historicalSchema) {
            raw.execute(sql);
          }
          raw.execute(
            "INSERT INTO positions VALUES ('demo','audio',1,'p1',2,3,4)",
          );
          raw.execute(
            "INSERT INTO installed_bundles VALUES ('fr','v1','${'a' * 64}','models/fr/v1','ready',5)",
          );
          raw.execute('PRAGMA user_version=1');
          final pages =
              raw.select('PRAGMA page_count').single['page_count'] as int;
          raw.execute('PRAGMA max_page_count=${pages + 8}');
        },
      ),
    );
    try {
      await expectLater(
        db.initialize(),
        throwsA(
          isA<SqliteException>().having(
            (error) => error.resultCode,
            'SQLITE_FULL',
            13,
          ),
        ),
      );
    } finally {
      await db.close();
    }
    final reopened = PrototypeDatabase(
      NativeDatabase(
        file,
        setup: (raw) {
          expect(raw.select('PRAGMA user_version').single['user_version'], 1);
          expect(
            raw
                .select(
                  "SELECT name FROM sqlite_master WHERE name LIKE 'book%'",
                )
                .isEmpty,
            true,
          );
          expect(
            raw.select('SELECT revision FROM positions').single['revision'],
            3,
          );
          expect(
            raw
                .select('SELECT manifest_digest FROM installed_bundles')
                .single['manifest_digest'],
            'a' * 64,
          );
          raw.execute('PRAGMA max_page_count=1073741823');
        },
      ),
    );
    try {
      await reopened.initialize();
      expect(
        (await reopened.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        3,
      );
    } finally {
      await reopened.close();
    }
  });
}
