// Explicitly selected test, outside the ordinary suite; only an owned private copy.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:prototype/app/dependencies.dart';
import 'package:prototype/features/model_setup/model_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real snapshot migrates without losing positions, identity or installed voice', () async {
    final pointer = jsonDecode(
      File('validation/epub/private/current-rehearsal.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final root = Directory(pointer['relativeRoot'] as String);
    final checked = await root.resolveSymbolicLinks();
    expect(p.isWithin(p.absolute('validation/epub/private'), checked), true);
    expect(p.basename(checked).startsWith('migration-rehearsal-'), true);
    final ownership = jsonDecode(
      File(p.join(checked, 'rehearsal-owned.json')).readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(ownership['initialSchema'], 1);
    final bytes = await File('assets/models/manifest.json').readAsBytes();
    final catalog = ModelCatalog.fromBytes(bytes);
    final app = await AppDependencies.open(
      directory: Directory(checked),
      loadSpeechManifest: () async => ByteData.sublistView(bytes),
    );
    try {
      final version =
          (await app.database.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single;
      expect(version, 2);
      for (final entry
          in (ownership['queries'] as Map<String, dynamic>).entries) {
        final rows = await app.database
            .customSelect(entry.value as String)
            .get();
        final actual = sha256
            .convert(
              utf8.encode(
                jsonEncode(rows.map((r) => r.data.values.toList()).toList()),
              ),
            )
            .toString();
        expect(actual, (ownership['tableHashes'] as Map)[entry.key]);
      }
      expect(await app.database.isBundleReady(catalog.bundle), true);
      final tables = await app.database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'book%'",
          )
          .get();
      expect(tables.length, 9);
      File(
        'validation/epub/reports/migration-rehearsal.json',
      ).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
          'status': 'passed',
          'sourceBackupSha256': ownership['sourceBackupSha256'],
          'schemaBefore': 1,
          'schemaAfter': version,
          'preservedTables': ['positions', 'bundle identity/path/status', 'operations'],
          'actualSevenFileVoiceReattested': true,
          'newBookTables': tables.length,
          'phoneModified': false,
          'androidPlayback': 'not_evaluated',
        })}\n',
      );
    } finally {
      await app.dispose();
    }
  });
}
