import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/app_error.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/infrastructure/database/position_repository.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';

void main() {
  late PrototypeDatabase db;
  late PositionRepository positions;
  final text = DemoText(
    id: 't',
    corpusVersion: 1,
    title: 'Test',
    passages: [
      Passage(id: 'p', textId: 't', ordinal: 0, text: 'Bonjour 😀 le jardin.'),
    ],
  );
  Locator at(int offset, {int version = 1}) => Locator(
    textId: 't',
    corpusVersion: version,
    passageId: 'p',
    offsetUtf16: offset,
  );
  setUp(() async {
    db = PrototypeDatabase(NativeDatabase.memory());
    await db.initialize();
    positions = PositionRepository(db);
  });
  tearDown(() async {
    await positions.flush();
    await db.close();
  });

  test('visual and audio writes remain independent and ordered', () async {
    final writes = [
      positions.save(text, at(0), ReadingMode.audio),
      positions.save(text, at(8), ReadingMode.visual),
      positions.save(text, at(11), ReadingMode.audio),
    ];
    await Future.wait(writes);
    expect(
      (await positions.read(text, ReadingMode.visual))!.locator.offsetUtf16,
      8,
    );
    expect(
      (await positions.read(text, ReadingMode.audio))!.locator.offsetUtf16,
      11,
    );
    expect((await positions.read(text, ReadingMode.audio))!.revision, 2);
  });
  test(
    'obsolete generation never writes and surrogate split is rejected',
    () async {
      expect(
        await positions.save(
          text,
          at(0),
          ReadingMode.audio,
          isCurrent: () => false,
        ),
        isNull,
      );
      expect(await positions.read(text, ReadingMode.audio), isNull);
      await expectLater(
        positions.save(text, at(9), ReadingMode.audio),
        throwsA(isA<AppError>()),
      );
    },
  );
  test(
    'stale revision fails without claiming the new position was saved',
    () async {
      await positions.save(text, at(0), ReadingMode.audio);
      await db.savePosition(
        text,
        at(8),
        ReadingMode.audio,
        expectedRevision: 1,
        updatedAt: DateTime.now().toUtc(),
      );
      await expectLater(
        positions.save(text, at(11), ReadingMode.audio),
        throwsA(
          isA<AppError>().having(
            (e) => e.code,
            'code',
            ErrorCode.revisionConflict,
          ),
        ),
      );
      expect(
        (await db.readPosition('t', ReadingMode.audio))!.locator.offsetUtf16,
        8,
      );
    },
  );
  test('unknown corpus version is reported without erasing the row', () async {
    await db.customStatement(
      "INSERT INTO positions VALUES ('t','audio',2,'p',0,1,1)",
    );
    await expectLater(
      positions.read(text, ReadingMode.audio),
      throwsA(isA<AppError>()),
    );
    expect(
      (await db.readPosition('t', ReadingMode.audio))!.locator.corpusVersion,
      2,
    );
  });
}
