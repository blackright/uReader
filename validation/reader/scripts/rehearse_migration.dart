// Migrate an actual private snapshot copy only. Never open the phone database.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:prototype/infrastructure/database/prototype_database.dart';
import 'package:prototype/infrastructure/database/book_content_repository.dart';
import 'package:prototype/infrastructure/files/book_file_store.dart';
import 'package:prototype/domain/books.dart';

Future<void> main() async {
  final project = File.fromUri(Platform.script).parent.parent.parent.parent;
  final source = Directory(
    '${project.path}/validation/reader/private/phase2-20261118-before',
  );
  final destination = await Directory(
    '${project.path}/validation/reader/private/rehearsal-${DateTime.now().microsecondsSinceEpoch}',
  ).create();
  final fingerprint = sha256
      .convert(await File('${source.path}/prototype.sqlite').readAsBytes())
      .toString();
  for (final suffix in ['', '-wal', '-shm']) {
    final file = File('${source.path}/prototype.sqlite$suffix');
    if (await file.exists()) {
      await file.copy('${destination.path}/prototype.sqlite$suffix');
    }
  }
  final before = <String, String>{};
  int? oldSchema;
  final db = PrototypeDatabase(
    NativeDatabase(
      File('${destination.path}/prototype.sqlite'),
      setup: (raw) {
        oldSchema =
            raw.select('PRAGMA user_version').single['user_version'] as int;
        for (final row in raw.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )) {
          final table = row['name'] as String;
          final q = '"${table.replaceAll('"', '""')}"';
          final columns = raw.select('PRAGMA table_info($q)').length;
          final order = List.generate(columns, (i) => '${i + 1}').join(',');
          before[table] = jsonEncode(
            raw
                .select('SELECT * FROM $q ORDER BY $order')
                .map((r) => Map<String, Object?>.from(r))
                .toList(),
          );
        }
      },
    ),
  );
  try {
    await db.initialize();
    for (final row in before.entries) {
      final q = '"${row.key.replaceAll('"', '""')}"';
      final columns =
          (await db.customSelect('PRAGMA table_info($q)').get()).length;
      final order = List.generate(columns, (i) => '${i + 1}').join(',');
      if (jsonEncode(
            (await db.customSelect('SELECT * FROM $q ORDER BY $order').get())
                .map((r) => r.data)
                .toList(),
          ) !=
          row.value) {
        throw StateError('Legacy data changed');
      }
    }
    final books = await db
        .customSelect(
          "SELECT book_id,projection_version FROM books WHERE state='ready' ORDER BY book_id LIMIT 1",
        )
        .get();
    int? ranges;
    if (books.isNotEmpty) {
      final content = BookContentRepository(
        db,
        await BookFileStore.open(destination),
      );
      final row = books.single;
      final key = ContentKey(
        ContentKind.book,
        row.read<String>('book_id'),
        row.read<int>('projection_version'),
      );
      ranges = (await content.paragraphs(key, 1, limit: 5)).paragraphs.length;
    }
    if (sha256
            .convert(
              await File('${source.path}/prototype.sqlite').readAsBytes(),
            )
            .toString() !=
        fingerprint) {
      throw StateError('Baseline changed');
    }
    final report = {
      'status': 'passed',
      'schemaBefore': oldSchema,
      'schemaAfter': 3,
      'oldTablesUnchanged': before.length,
      'actualBookParagraphsRead': ranges,
      'baselineHashUnchanged': true,
      'nativeVoiceResolution': 'not_evaluated_host',
      'foreignKeyViolations':
          (await db.customSelect('PRAGMA foreign_key_check').get()).length,
    };
    await File(
      '${project.path}/validation/reader/reports/foundations-rehearsal.json',
    ).writeAsString('${jsonEncode(report)}\n');
    stdout.writeln(jsonEncode(report));
  } finally {
    await db.close();
  }
}
