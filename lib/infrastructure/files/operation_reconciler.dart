import 'dart:io';

import '../../domain/app_error.dart';
import '../../domain/storage.dart';
import '../diagnostics/safe_diagnostics.dart';

enum RecoveryCheckpoint { beforePublish, afterPublish }

class RecoverySummary {
  const RecoverySummary(this.completed, this.failed);
  final int completed;
  final int failed;
}

/// La confiance vient du catalogue embarqué injecté, jamais du journal seul.
class OperationReconciler {
  OperationReconciler({
    required this.journal,
    required this.files,
    required this.resolveTrustedBundle,
    required this.diagnostics,
    this.checkpoint,
  });
  final OperationJournal journal;
  final PrivateFiles files;
  final BundleTrustResolver resolveTrustedBundle;
  final SafeDiagnostics diagnostics;
  final Future<void> Function(RecoveryCheckpoint point)? checkpoint;

  Future<RecoverySummary>? _running;

  Future<RecoverySummary> reconcile() =>
      _running ??= _reconcile().whenComplete(() => _running = null);

  Future<RecoverySummary> _reconcile() async {
    var completed = 0;
    var failed = 0;
    for (final operation in await journal.pendingOperations()) {
      try {
        if (operation.kind == OperationKind.delete) {
          await files.delete('cache/audio');
          await files.delete('cache/native');
          await files.delete(operation.finalDirectory);
          await journal.completeDelete(operation);
        } else {
          final trusted = await resolveTrustedBundle(
            operation.bundleId,
            operation.bundleVersion,
            operation.manifestDigest,
          );
          if (trusted == null ||
              trusted.id != operation.bundleId ||
              trusted.version != operation.bundleVersion ||
              trusted.manifestDigest != operation.manifestDigest) {
            throw const AppError(ErrorCode.modelIntegrityFailed);
          }
          if (await files.exists(operation.finalDirectory)) {
            if (!await files.verify(operation.finalDirectory, trusted.files)) {
              throw const AppError(ErrorCode.modelIntegrityFailed);
            }
          } else {
            if (!await files.verify(
              operation.stagingDirectory,
              trusted.files,
            )) {
              // Copie interrompue : ne jamais activer une ressource incomplète.
              await files.delete(operation.stagingDirectory);
              await journal.forgetOperation(operation.id);
              diagnostics.record(
                DiagnosticEvent.recoveryFailed,
                error: ErrorCode.modelIntegrityFailed,
              );
              failed++;
              continue;
            }
            await checkpoint?.call(RecoveryCheckpoint.beforePublish);
            await files.publish(
              operation.stagingDirectory,
              operation.finalDirectory,
            );
            await checkpoint?.call(RecoveryCheckpoint.afterPublish);
          }
          await files.delete(operation.stagingDirectory);
          await journal.completeInstall(operation, trusted);
        }
        completed++;
        diagnostics.record(DiagnosticEvent.recoveryCompleted);
      } on AppError catch (error) {
        failed++;
        await journal.markOperationError(operation.id, error.code);
        diagnostics.record(DiagnosticEvent.recoveryFailed, error: error.code);
      } on FileSystemException {
        failed++;
        await journal.markOperationError(
          operation.id,
          ErrorCode.storageUnavailable,
        );
        diagnostics.record(
          DiagnosticEvent.recoveryFailed,
          error: ErrorCode.storageUnavailable,
        );
      }
    }
    // Une copie abandonnée avant l'enregistrement du journal n'est jamais activée.
    final retained = (await journal.pendingOperations())
        .map((op) => op.id)
        .toSet();
    for (final id in await files.stagingDirectories()) {
      if (!retained.contains(id)) {
        try {
          await files.delete('staging/$id');
        } on AppError catch (error) {
          failed++;
          diagnostics.record(DiagnosticEvent.recoveryFailed, error: error.code);
        } on FileSystemException {
          failed++;
          diagnostics.record(
            DiagnosticEvent.recoveryFailed,
            error: ErrorCode.storageUnavailable,
          );
        }
      }
    }
    return RecoverySummary(completed, failed);
  }
}
