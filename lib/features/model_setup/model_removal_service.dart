import '../../domain/app_error.dart';
import '../../domain/storage.dart';
import '../../infrastructure/database/prototype_database.dart';
import '../../infrastructure/files/private_file_store.dart';
import 'model_operation_gate.dart';

class ModelRemovalService {
  ModelRemovalService({
    required this.files,
    required this.database,
    required this.releaseVoice,
    required this.resumeVoice,
    ModelOperationGate? gate,
  }) : gate = gate ?? ModelOperationGate();
  final ModelOperationGate gate;
  final PrivateFileStore files;
  final PrototypeDatabase database;
  final Future<void> Function() releaseVoice;
  final void Function() resumeVoice;
  bool _removing = false;
  Future<void>? _pending;
  Future<void> close() async {
    await _pending;
  }

  Future<void> remove(BundleDescriptor bundle) {
    if (_pending != null) {
      return Future.error(const AppError(ErrorCode.resourceInUse));
    }
    final future = _remove(bundle);
    _pending = future;
    return future.whenComplete(() {
      _pending = null;
    });
  }

  Future<void> _remove(BundleDescriptor bundle) async {
    if (_removing || !gate.enter()) {
      throw const AppError(ErrorCode.resourceInUse);
    }
    _removing = true;
    try {
      await releaseVoice();
      // A stale install must not resurrect this version after an explicit removal.
      for (final pending in await database.pendingOperations()) {
        if (pending.kind == OperationKind.install &&
            pending.bundleId == bundle.id &&
            pending.bundleVersion == bundle.version) {
          await files.delete(pending.stagingDirectory);
          await database.forgetOperation(pending.id);
        }
      }
      final op = JournalOperation(
        id: 'delete-${DateTime.now().microsecondsSinceEpoch}',
        kind: OperationKind.delete,
        bundleId: bundle.id,
        bundleVersion: bundle.version,
        manifestDigest: bundle.manifestDigest,
      );
      await database.saveOperation(op);
      // All caches belong to this single-voice prototype; no personal books are involved.
      await files.delete('cache/audio');
      await files.delete('cache/native');
      await files.delete(bundle.directory);
      await database.completeDelete(op);
    } finally {
      _removing = false;
      gate.leave();
      resumeVoice();
    }
  }
}
