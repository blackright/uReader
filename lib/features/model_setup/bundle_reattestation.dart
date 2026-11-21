import 'dart:io';

import '../../domain/app_error.dart';
import '../../domain/storage.dart';
import '../../infrastructure/database/prototype_database.dart';
import 'model_catalog.dart';
import 'model_operation_gate.dart';

/// A new application manifest may reattest an existing ready row, never an orphan.
class BundleReattestation {
  BundleReattestation({
    required this.database,
    required this.files,
    required this.gate,
  });
  final PrototypeDatabase database;
  final PrivateFiles files;
  final ModelOperationGate gate;
  Future<bool> run(ModelCatalog catalog) async {
    if (!catalog.demonstrated || !gate.enter()) return false;
    try {
      final previous = await database.reattestableDigest(catalog.bundle);
      if (previous == null) return false;
      if (previous == catalog.bundle.manifestDigest) return true;
      if (!await files.verify(catalog.bundle.directory, catalog.bundle.files)) {
        return false;
      }
      return await database.compareAndSwapBundleDigest(
        catalog.bundle,
        previous,
      );
    } on AppError {
      return false;
    } on FileSystemException {
      return false;
    } finally {
      gate.leave();
    }
  }
}
