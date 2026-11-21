import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';

void main() {
  late PrototypeDatabase db;
  final text = DemoText(
    id: 'demo',
    corpusVersion: 1,
    title: 'T',
    passages: [Passage(id: 'p1', textId: 'demo', ordinal: 0, text: 'Bonjour')],
  );
  Locator at(int offset) => Locator(
    textId: 'demo',
    corpusVersion: 1,
    passageId: 'p1',
    offsetUtf16: offset,
  );
  setUp(() async {
    db = PrototypeDatabase(NativeDatabase.memory());
    await db.initialize();
  });
  tearDown(() => db.close());

  test('Sépare visuel/audio et refuse une révision obsolète', () async {
    await db.savePosition(
      text,
      at(1),
      ReadingMode.visual,
      expectedRevision: 0,
      updatedAt: DateTime.utc(2026),
    );
    await db.savePosition(
      text,
      at(2),
      ReadingMode.audio,
      expectedRevision: 0,
      updatedAt: DateTime.utc(2026),
    );
    await expectLater(
      db.savePosition(
        text,
        at(3),
        ReadingMode.visual,
        expectedRevision: 0,
        updatedAt: DateTime.utc(2026),
      ),
      throwsA(isA<AppError>()),
    );
    expect(
      (await db.readPosition('demo', ReadingMode.visual))!.locator.offsetUtf16,
      1,
    );
    expect(
      (await db.readPosition('demo', ReadingMode.audio))!.locator.offsetUtf16,
      2,
    );
  });
  test(
    'Références invalides et contraintes SQL ne modifient pas les données',
    () async {
      await expectLater(
        db.savePosition(
          text,
          Locator(
            textId: 'other',
            corpusVersion: 1,
            passageId: 'p1',
            offsetUtf16: 0,
          ),
          ReadingMode.visual,
          expectedRevision: 0,
          updatedAt: DateTime.utc(2026),
        ),
        throwsA(isA<AppError>()),
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO positions VALUES ('t','wrong',1,'p',0,1,0)",
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO positions VALUES ('t','visual',1,'p',-1,1,0)",
        ),
        throwsA(anything),
      );
      expect(await db.readPosition('demo', ReadingMode.visual), isNull);
    },
  );
  test('Échec de transaction conserve la position précédente', () async {
    await db.savePosition(
      text,
      at(1),
      ReadingMode.visual,
      expectedRevision: 0,
      updatedAt: DateTime.utc(2026),
    );
    await expectLater(
      db.transaction(() async {
        await db.savePosition(
          text,
          at(2),
          ReadingMode.visual,
          expectedRevision: 1,
          updatedAt: DateTime.utc(2026),
        );
        throw const AppError(ErrorCode.storageUnavailable);
      }),
      throwsA(isA<AppError>()),
    );
    expect((await db.readPosition('demo', ReadingMode.visual))!.revision, 1);
  });
  test('Réouverture durable du schéma 2 et refus non destructif d’une version inconnue', () async {
    final directory = await Directory.systemTemp.createTemp('ureader-db-');
    final file = File('${directory.path}/data.sqlite');
    await db.close();
    db = PrototypeDatabase(NativeDatabase(file));
    await db.savePosition(
      text,
      at(2),
      ReadingMode.audio,
      expectedRevision: 0,
      updatedAt: DateTime.utc(2026),
    );
    await db.close();
    db = PrototypeDatabase(NativeDatabase(file));
    expect(
      (await db.readPosition('demo', ReadingMode.audio))!.locator.offsetUtf16,
      2,
    );
    await db.customStatement('PRAGMA user_version = 99');
    await db.close();
    db = PrototypeDatabase(NativeDatabase(file));
    await expectLater(db.initialize(), throwsA(isA<AppError>()));
    await db.close();
    // Test seulement : rétablir l'en-tête pour vérifier la préservation des données.
    db = PrototypeDatabase(
      NativeDatabase(
        file,
        setup: (connection) => connection.execute('PRAGMA user_version = 3'),
      ),
    );
    expect(
      (await db.readPosition('demo', ReadingMode.audio))!.locator.offsetUtf16,
      2,
    );
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'Deux écritures concurrentes ne peuvent pas utiliser la même révision',
    () async {
      Future<bool> save(int offset) async {
        try {
          await db.savePosition(
            text,
            at(offset),
            ReadingMode.visual,
            expectedRevision: 0,
            updatedAt: DateTime.utc(2026),
          );
          return true;
        } on AppError catch (error) {
          expect(error.code, ErrorCode.revisionConflict);
          return false;
        }
      }

      expect(
        (await Future.wait([save(1), save(2)])).where((ok) => ok).length,
        1,
      );
      expect((await db.readPosition('demo', ReadingMode.visual))!.revision, 1);
    },
  );

  test('Refuse un schéma v3 remis à zéro sans perdre les repères', () async {
    final directory = await Directory.systemTemp.createTemp('ureader-recover-');
    final file = File('${directory.path}/data.sqlite');
    await db.close();
    db = PrototypeDatabase(NativeDatabase.createInBackground(file));
    try {
      await db.savePosition(
        text,
        at(2),
        ReadingMode.audio,
        expectedRevision: 0,
        updatedAt: DateTime.utc(2026),
      );
      // Reproduire l'ancien arrêt entre création des tables et version finale.
      await db.customStatement('PRAGMA user_version = 0');
      await db.close();
      db = PrototypeDatabase(NativeDatabase.createInBackground(file));
      await expectLater(db.initialize(), throwsA(isA<AppError>()));
      await db.close();
      // Test-only header restoration to inspect that the refused database is intact.
      db = PrototypeDatabase(
        NativeDatabase(
          file,
          setup: (raw) => raw.execute('PRAGMA user_version=3'),
        ),
      );
      await db.initialize();
      expect(
        (await db.readPosition('demo', ReadingMode.audio))!.locator.offsetUtf16,
        2,
      );
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        3,
      );
    } finally {
      await db.close();
      await directory.delete(recursive: true);
    }
  });

  test('Refuse les schémas zéro ambigus sans modifier version ni données', () async {
    for (final mutation in [
      'DROP TABLE operations',
      'CREATE TABLE unexpected (value TEXT)',
      'DROP INDEX operations_phase',
      'CREATE TRIGGER unexpected AFTER INSERT ON positions BEGIN SELECT 1; END',
      'ALTER TABLE positions ADD COLUMN unexpected TEXT',
    ]) {
      final directory = await Directory.systemTemp.createTemp(
        'ureader-reject-',
      );
      final file = File('${directory.path}/data.sqlite');
      await db.close();
      db = PrototypeDatabase(NativeDatabase(file));
      await db.savePosition(
        text,
        at(1),
        ReadingMode.visual,
        expectedRevision: 0,
        updatedAt: DateTime.utc(2026),
      );
      await db.customStatement(mutation);
      await db.customStatement('PRAGMA user_version = 0');
      await db.close();
      final before = await file.readAsBytes();
      db = PrototypeDatabase(NativeDatabase.createInBackground(file));
      try {
        await expectLater(
          db.initialize(),
          throwsA(
            isA<AppError>().having(
              (e) => e.code,
              'code',
              ErrorCode.unsupportedSchema,
            ),
          ),
        );
      } finally {
        await db.close();
      }
      expect(await file.readAsBytes(), before);
      await directory.delete(recursive: true);
    }
  });
}
