import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/app_error.dart';
import '../../domain/storage.dart';
import '../../infrastructure/database/prototype_database.dart';
import '../../infrastructure/files/private_file_store.dart';
import 'model_catalog.dart';
import 'model_operation_gate.dart';

abstract interface class LocalBundleSource {
  Future<bool> chooseFolder();
  Stream<List<int>> readFile(String name);
  Future<void> close();
}

enum ModelSetupState {
  absent,
  checking,
  choosing,
  copying,
  verifying,
  publishing,
  ready,
  error,
}

class ModelInstaller extends ChangeNotifier {
  ModelInstaller({
    required this.catalog,
    required this.files,
    required this.database,
    required this.source,
    this.beforePublication,
    this.afterPublication,
    this.onSettled,
    this.hasSpace,
    ModelOperationGate? gate,
  }) : gate = gate ?? ModelOperationGate();
  final ModelOperationGate gate;
  final ModelCatalog catalog;
  final PrivateFileStore files;
  final PrototypeDatabase database;
  final LocalBundleSource source;
  final Future<void> Function()? beforePublication, afterPublication;
  final void Function()? onSettled;
  final Future<bool> Function(int bytes)? hasSpace;
  ModelSetupState state = ModelSetupState.absent;
  AppError? error;
  int copiedBytes = 0;
  bool resourcesPresent = false;
  int _revision = 0;
  bool _cancelled = false, _closed = false;
  Future<void>? _running;
  bool get busy => _running != null || gate.active;
  void _state(ModelSetupState value) {
    state = value;
    if (!_closed) notifyListeners();
  }

  Future<void> refresh() async {
    if (busy) return;
    final revision = ++_revision;
    _state(ModelSetupState.checking);
    try {
      resourcesPresent = await files.exists(catalog.bundle.directory);
      final ready =
          await database.isBundleReady(catalog.bundle) &&
          await files.verify(catalog.bundle.directory, catalog.bundle.files);
      if (revision == _revision && !busy) {
        _state(ready ? ModelSetupState.ready : ModelSetupState.absent);
      }
    } catch (_) {
      error = const AppError(ErrorCode.storageUnavailable);
      _state(ModelSetupState.error);
    }
  }

  void _check() {
    if (_cancelled || _closed) throw const AppError(ErrorCode.cancelled);
  }

  Future<void> cancel() async {
    _cancelled = true;
    try {
      await source.close();
    } catch (_) {
      /* Cancellation flag fences all later chunks. */
    }
  }

  Future<void> install() {
    if (_running != null) return _running!;
    if (!gate.enter()) {
      error = const AppError(ErrorCode.resourceInUse);
      _state(ModelSetupState.error);
      return Future.value();
    }
    _revision++;
    _cancelled = false;
    error = null;
    copiedBytes = 0;
    final future = _install();
    _running = future;
    return future.whenComplete(() {
      _running = null;
      gate.leave();
      if (!_closed) notifyListeners();
    });
  }

  Future<void> _install() async {
    JournalOperation? op;
    var published = false;
    try {
      if (!catalog.demonstrated) {
        throw const AppError(ErrorCode.engineUnavailable);
      }
      _state(ModelSetupState.choosing);
      if (!await source.chooseFolder()) {
        throw const AppError(ErrorCode.cancelled);
      }
      _check();
      final b = catalog.bundle;
      op = JournalOperation(
        id: 'install-${DateTime.now().microsecondsSinceEpoch}',
        kind: OperationKind.install,
        bundleId: b.id,
        bundleVersion: b.version,
        manifestDigest: b.manifestDigest,
      );
      await database.saveOperation(op);
      _state(ModelSetupState.copying);
      if (await files.exists(b.directory)) {
        if (!await files.verify(b.directory, b.files)) {
          throw const AppError(ErrorCode.modelIntegrityFailed);
        }
      } else {
        if (hasSpace != null &&
            !await hasSpace!(catalog.totalBytes + 8 * 1024 * 1024)) {
          throw const AppError(ErrorCode.storageUnavailable);
        }
        for (final file in b.files) {
          _check();
          await files.writeStagedStream(
            op.id,
            file.relativePath,
            source.readFile(file.relativePath).map((chunk) {
              _check();
              copiedBytes += chunk.length;
              if (copiedBytes > catalog.totalBytes) {
                throw const AppError(ErrorCode.storageLimitExceeded);
              }
              if (!_closed) notifyListeners();
              return chunk;
            }),
            maxBytes: file.byteSize,
          );
        }
        _state(ModelSetupState.verifying);
        if (!await files.verify(op.stagingDirectory, b.files)) {
          throw const AppError(ErrorCode.modelIntegrityFailed);
        }
        _check();
        await beforePublication?.call();
        _check();
        _state(ModelSetupState.publishing);
        await files.publish(op.stagingDirectory, b.directory);
        published = true;
        await afterPublication?.call();
      }
      // Publication and ready commit finish together; cancellation after rename is recovery-safe.
      await database.completeInstall(op, b);
      resourcesPresent = true;
      _state(ModelSetupState.ready);
    } catch (failure) {
      if (failure is Error) rethrow;
      error = failure is AppError
          ? failure
          : const AppError(ErrorCode.storageUnavailable);
      if (op != null && !published) {
        try {
          await files.delete(op.stagingDirectory);
          await database.forgetOperation(op.id);
        } catch (_) {
          /* Journal retained for recovery. */
        }
      }
      _state(ModelSetupState.error);
    } finally {
      try {
        await source.close();
      } catch (_) {
        /* No selected folder retained. */
      }
      onSettled?.call();
    }
  }

  Future<void> close() async {
    _closed = true;
    await cancel();
    await _running;
    super.dispose();
  }
}
