import 'package:flutter/services.dart';

import '../../domain/app_error.dart';
import '../../features/model_setup/model_installer.dart';

class AndroidLocalBundleSource implements LocalBundleSource {
  static const _channel = MethodChannel(
    'com.ureader.prototype/local_bundle/v1',
  );
  int _epoch = 0;
  bool _touched = false;
  Future<bool> hasSpace(int bytes) async =>
      (await _invoke<num>('availableBytes') ?? 0) >= bytes;
  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      final result = _channel.invokeMethod<T>(method, args);
      return await (method == 'chooseFolder'
          ? result
          : result.timeout(const Duration(seconds: 30)));
    } on PlatformException catch (error) {
      throw AppError(
        ErrorCode.values.where((code) => code.name == error.code).firstOrNull ??
            ErrorCode.storageUnavailable,
      );
    } on MissingPluginException {
      throw const AppError(ErrorCode.engineUnavailable);
    }
  }

  @override
  Future<bool> chooseFolder() async {
    final epoch = ++_epoch;
    _touched = true;
    final selected = await _invoke<bool>('chooseFolder');
    return epoch == _epoch && selected == true;
  }

  @override
  Stream<List<int>> readFile(String name) async* {
    final epoch = _epoch;
    await _invoke<void>('open', {'name': name});
    while (epoch == _epoch) {
      final chunk = await _invoke<Uint8List>('read');
      if (epoch != _epoch) throw const AppError(ErrorCode.cancelled);
      if (chunk == null || chunk.isEmpty) break;
      if (chunk.length > 65536) {
        throw const AppError(ErrorCode.storageLimitExceeded);
      }
      yield chunk;
    }
    if (epoch != _epoch) throw const AppError(ErrorCode.cancelled);
  }

  @override
  Future<void> close() async {
    ++_epoch;
    if (_touched) {
      await _invoke<void>('close');
      _touched = false;
    }
  }
}

class UnavailableLocalBundleSource implements LocalBundleSource {
  @override
  Future<bool> chooseFolder() async =>
      throw const AppError(ErrorCode.engineUnavailable);
  @override
  Stream<List<int>> readFile(String name) =>
      Stream.error(const AppError(ErrorCode.engineUnavailable));
  @override
  Future<void> close() async {}
}
