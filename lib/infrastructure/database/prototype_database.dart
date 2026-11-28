import 'package:drift/drift.dart';
// Drift 2.35.4 verrouillé : déballer uniquement nos erreurs publiques entre isolates.
// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;

import '../../domain/app_error.dart';
import '../../domain/content.dart';
import '../../domain/ports.dart';
import '../../domain/storage.dart';
import 'book_schema.dart';
import 'reader_schema.dart';

/// Schéma réduit SQL explicite, exécuté par Drift sans génération de code.
class PrototypeDatabase extends GeneratedDatabase implements PrototypeStore {
  PrototypeDatabase(super.executor);
  @override
  int get schemaVersion => 4;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await transaction(() async {
        final existing = await customSelect(
          'SELECT type, name, sql FROM sqlite_master WHERE sql IS NOT NULL',
        ).get();
        if (existing.isEmpty) {
          for (final statement in _schema) {
            await customStatement(statement);
          }
        } else {
          await _verifySchema(_schema);
        }
        for (final sql in [
          ...BookSchema.statements,
          ...ReaderSchema.currentStatements,
        ]) {
          await customStatement(sql);
        }
        // La version est durable avec les tables, pas seulement après leur COMMIT.
        await customStatement('PRAGMA user_version = 4');
      });
    },
    onUpgrade: (_, from, to) async {
      if ((from != 1 && from != 2 && from != 3) || to != 4) {
        throw const AppError(ErrorCode.unsupportedSchema);
      }
      await transaction(() async {
        await _verifySchema(
          from == 1
              ? _schema
              : [
                  ..._schema,
                  ...BookSchema.statements,
                  if (from == 3) ...ReaderSchema.statements,
                ],
        );
        if (from == 1) {
          for (final sql in BookSchema.statements) {
            await customStatement(sql);
          }
        }
        if (from == 3) {
          await customStatement(
            'ALTER TABLE experience_preferences RENAME TO experience_preferences_v3',
          );
          await customStatement(ReaderSchema.currentStatements.last);
          await customStatement(
            'INSERT INTO experience_preferences SELECT * FROM experience_preferences_v3',
          );
          await customStatement('DROP TABLE experience_preferences_v3');
        } else {
          for (final sql in ReaderSchema.currentStatements) {
            await customStatement(sql);
          }
        }
        await customStatement('PRAGMA user_version=4');
      });
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA synchronous = FULL');
      await _verifySchema([
        ..._schema,
        ...BookSchema.statements,
        ...ReaderSchema.currentStatements,
      ]);
    },
  );

  Future<void> _verifySchema(List<String> schema) async {
    final rows = await customSelect(
      'SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL',
    ).get();
    final expected = {for (final sql in schema) _canonicalSql(sql)};
    final actual = {
      for (final row in rows) _canonicalSql(row.read<String>('sql')),
    };
    if (rows.length != expected.length ||
        actual.length != expected.length ||
        !actual.containsAll(expected)) {
      throw const AppError(ErrorCode.unsupportedSchema);
    }
    final integrity = await customSelect('PRAGMA quick_check').get();
    if (integrity.length != 1 || integrity.single.data.values.single != 'ok') {
      throw const AppError(ErrorCode.unsupportedSchema);
    }
    final foreign = await customSelect('PRAGMA foreign_key_check').get();
    if (foreign.isNotEmpty) throw const AppError(ErrorCode.unsupportedSchema);
  }

  // SQL produit par cette application : tolérer uniquement les espaces de formatage.
  // La casse, les littéraux, contraintes et noms restent comparés strictement.
  static String _canonicalSql(String sql) =>
      sql.replaceAll(RegExp(r'\s+'), ' ').trim();

  static const _schema = [
    """CREATE TABLE positions (
      text_id TEXT NOT NULL, mode TEXT NOT NULL CHECK(mode IN ('visual','audio')),
      corpus_version INTEGER NOT NULL CHECK(corpus_version > 0),
      passage_id TEXT NOT NULL, offset_utf16 INTEGER NOT NULL CHECK(offset_utf16 >= 0),
      revision INTEGER NOT NULL CHECK(revision > 0), updated_at INTEGER NOT NULL,
      PRIMARY KEY(text_id, mode))""",
    """CREATE TABLE installed_bundles (
      bundle_id TEXT NOT NULL, version TEXT NOT NULL,
      manifest_digest TEXT NOT NULL CHECK(length(manifest_digest) = 64),
      relative_directory TEXT NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('ready')),
      verified_at INTEGER NOT NULL,
      PRIMARY KEY(bundle_id, version))""",
    """CREATE TABLE operations (
      id TEXT PRIMARY KEY NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('install','delete')),
      bundle_id TEXT NOT NULL, bundle_version TEXT NOT NULL,
      manifest_digest TEXT NOT NULL CHECK(length(manifest_digest) = 64),
      phase TEXT NOT NULL CHECK(phase IN ('pending','published','error')),
      error_code TEXT, updated_at INTEGER NOT NULL)""",
    'CREATE INDEX operations_phase ON operations(phase, updated_at)',
  ];

  @override
  Future<void> initialize() async {
    try {
      await customSelect('SELECT 1').get();
    } on DriftRemoteException catch (error) {
      Object cause = error;
      while (cause is DriftRemoteException) {
        cause = cause.remoteCause;
      }
      // Conserver uniquement nos erreurs publiques à travers l'isolate Drift.
      if (cause is AppError) throw cause;
      rethrow;
    }
  }

  @override
  Future<ResumePosition?> readPosition(String textId, ReadingMode mode) async {
    final row = await customSelect(
      'SELECT * FROM positions WHERE text_id = ? AND mode = ?',
      variables: [Variable(textId), Variable(mode.name)],
    ).getSingleOrNull();
    if (row == null) return null;
    return ResumePosition(
      locator: Locator(
        textId: row.read<String>('text_id'),
        corpusVersion: row.read<int>('corpus_version'),
        passageId: row.read<String>('passage_id'),
        offsetUtf16: row.read<int>('offset_utf16'),
      ),
      mode: mode,
      revision: row.read<int>('revision'),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('updated_at'),
        isUtc: true,
      ),
    );
  }

  Future<ResumePosition?> readLatestVisualPosition() async {
    final row = await customSelect(
      "SELECT text_id FROM positions WHERE mode = 'visual' ORDER BY updated_at DESC, text_id LIMIT 1",
    ).getSingleOrNull();
    return row == null
        ? null
        : readPosition(row.read<String>('text_id'), ReadingMode.visual);
  }

  @override
  Future<ResumePosition> savePosition(
    DemoText text,
    Locator locator,
    ReadingMode mode, {
    required int expectedRevision,
    required DateTime updatedAt,
  }) async {
    text.validate(locator);
    return transaction(() async {
      final existing = await readPosition(text.id, mode);
      if (existing != null &&
          existing.locator.corpusVersion != locator.corpusVersion) {
        throw const AppError(ErrorCode.invalidLocator);
      }
      if (expectedRevision < 0 ||
          (existing?.revision ?? 0) != expectedRevision) {
        throw const AppError(ErrorCode.revisionConflict);
      }
      final revision = expectedRevision + 1;
      await customStatement(
        'INSERT INTO positions VALUES (?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(text_id, mode) DO UPDATE SET corpus_version=excluded.corpus_version, '
        'passage_id=excluded.passage_id, offset_utf16=excluded.offset_utf16, '
        'revision=excluded.revision, updated_at=excluded.updated_at',
        [
          text.id,
          mode.name,
          locator.corpusVersion,
          locator.passageId,
          locator.offsetUtf16,
          revision,
          updatedAt.toUtc().millisecondsSinceEpoch,
        ],
      );
      return ResumePosition(
        locator: locator,
        mode: mode,
        revision: revision,
        updatedAt: updatedAt.toUtc(),
      );
    });
  }

  @override
  Future<void> saveOperation(JournalOperation operation) =>
      transaction(() async {
        final existing = await customSelect(
          'SELECT * FROM operations WHERE id = ?',
          variables: [Variable(operation.id)],
        ).getSingleOrNull();
        if (existing != null) {
          if (existing.read<String>('kind') != operation.kind.name ||
              existing.read<String>('bundle_id') != operation.bundleId ||
              existing.read<String>('bundle_version') !=
                  operation.bundleVersion ||
              existing.read<String>('manifest_digest') !=
                  operation.manifestDigest) {
            throw const AppError(ErrorCode.invalidContent);
          }
          return;
        }
        await customStatement(
          'INSERT INTO operations VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            operation.id,
            operation.kind.name,
            operation.bundleId,
            operation.bundleVersion,
            operation.manifestDigest,
            operation.phase.name,
            operation.errorCode?.name,
            DateTime.now().toUtc().millisecondsSinceEpoch,
          ],
        );
      });

  @override
  Future<List<JournalOperation>> pendingOperations() async {
    final rows = await customSelect(
      'SELECT * FROM operations ORDER BY updated_at, id',
    ).get();
    return rows
        .map(
          (r) => JournalOperation(
            id: r.read<String>('id'),
            kind: OperationKind.values.byName(r.read<String>('kind')),
            bundleId: r.read<String>('bundle_id'),
            bundleVersion: r.read<String>('bundle_version'),
            manifestDigest: r.read<String>('manifest_digest'),
            phase: OperationPhase.values.byName(r.read<String>('phase')),
            errorCode: r.readNullable<String>('error_code') == null
                ? null
                : ErrorCode.values.byName(r.read<String>('error_code')),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> markOperationError(String id, ErrorCode code) => customStatement(
    "UPDATE operations SET phase = 'error', error_code = ? WHERE id = ?",
    [code.name, id],
  );

  @override
  Future<void> forgetOperation(String id) =>
      customStatement('DELETE FROM operations WHERE id = ?', [id]);

  @override
  Future<void> completeInstall(
    JournalOperation operation,
    BundleDescriptor verified,
  ) => transaction(() async {
    if (operation.kind != OperationKind.install ||
        operation.bundleId != verified.id ||
        operation.bundleVersion != verified.version ||
        operation.manifestDigest != verified.manifestDigest) {
      throw const AppError(ErrorCode.modelIntegrityFailed);
    }
    await customStatement(
      "INSERT INTO installed_bundles VALUES (?, ?, ?, ?, 'ready', ?) "
      "ON CONFLICT(bundle_id, version) DO UPDATE SET manifest_digest=excluded.manifest_digest, "
      "relative_directory=excluded.relative_directory, verified_at=excluded.verified_at",
      [
        verified.id,
        verified.version,
        verified.manifestDigest,
        verified.directory,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ],
    );
    await forgetOperation(operation.id);
  });

  @override
  Future<void> completeDelete(JournalOperation operation) =>
      transaction(() async {
        await customStatement(
          'DELETE FROM installed_bundles WHERE bundle_id = ? AND version = ?',
          [operation.bundleId, operation.bundleVersion],
        );
        // Model removal/recovery clear the entire single-voice cache namespace.
        await customStatement('DELETE FROM book_audio_cache');
        await forgetOperation(operation.id);
      });

  Future<bool> isBundleReady(BundleDescriptor bundle) async {
    final rows = await customSelect(
      'SELECT manifest_digest FROM installed_bundles WHERE bundle_id = ? AND version = ? AND status = ?',
      variables: [
        Variable(bundle.id),
        Variable(bundle.version),
        const Variable('ready'),
      ],
    ).get();
    return rows.length == 1 &&
        rows.single.read<String>('manifest_digest') == bundle.manifestDigest;
  }

  Future<String?> reattestableDigest(BundleDescriptor bundle) async {
    final row = await customSelect(
      "SELECT manifest_digest FROM installed_bundles WHERE bundle_id=? AND version=? AND status='ready' AND relative_directory=? AND NOT EXISTS (SELECT 1 FROM operations WHERE bundle_id=? AND bundle_version=? AND kind='delete')",
      variables: [
        Variable(bundle.id),
        Variable(bundle.version),
        Variable(bundle.directory),
        Variable(bundle.id),
        Variable(bundle.version),
      ],
    ).getSingleOrNull();
    final digest = row?.read<String>('manifest_digest');
    return digest != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)
        ? digest
        : null;
  }

  Future<bool> compareAndSwapBundleDigest(
    BundleDescriptor bundle,
    String expected,
  ) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) return false;
    return await customUpdate(
          "UPDATE installed_bundles SET manifest_digest=?,verified_at=? WHERE bundle_id=? AND version=? AND manifest_digest=? AND status='ready' AND relative_directory=? AND NOT EXISTS (SELECT 1 FROM operations WHERE bundle_id=? AND bundle_version=? AND kind='delete')",
          variables: [
            Variable(bundle.manifestDigest),
            Variable(DateTime.now().toUtc().millisecondsSinceEpoch),
            Variable(bundle.id),
            Variable(bundle.version),
            Variable(expected),
            Variable(bundle.directory),
            Variable(bundle.id),
            Variable(bundle.version),
          ],
        ) ==
        1;
  }
}
