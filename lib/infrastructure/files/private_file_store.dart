import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/app_error.dart';
import '../../domain/storage.dart';

class ResourceLease {
  ResourceLease(this._release);
  void Function()? _release;
  void release() {
    _release?.call();
    _release = null;
  }
}

/// Les écritures de l'application sont sérialisées dans une racine privée.
/// Ceci n'est pas une protection contre un hôte compromis modifiant les liens
/// entre deux appels système (TOCTOU).
class PrivateFileStore implements PrivateFiles {
  PrivateFileStore._(this.root);
  final Directory root;
  Future<void> _tail = Future.value();
  final Map<String, int> _leases = {};

  static Future<PrivateFileStore> open(Directory directory) async {
    final absolute = p.normalize(p.absolute(directory.path));
    // Refuser les liens préexistants dans la chaîne, avant toute création.
    var cursor = absolute;
    while (true) {
      if (await FileSystemEntity.type(cursor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const AppError(ErrorCode.unsafePath);
      }
      final parent = p.dirname(cursor);
      if (parent == cursor) break;
      cursor = parent;
    }
    await Directory(absolute).create(recursive: true);
    return PrivateFileStore._(
      Directory(await Directory(absolute).resolveSymbolicLinks()),
    );
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<String> _resolve(String relative) async {
    validateRelativePath(relative);
    final components = relative.split('/');
    var cursor = root.path;
    // La racine doit elle-même rester un répertoire, pas un lien substitué.
    if (await FileSystemEntity.type(cursor, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const AppError(ErrorCode.unsafePath);
    }
    for (var i = 0; i < components.length; i++) {
      cursor = p.join(cursor, components[i]);
      if (!p.isWithin(root.path, cursor)) {
        throw const AppError(ErrorCode.unsafePath);
      }
      final type = await FileSystemEntity.type(cursor, followLinks: false);
      if (type == FileSystemEntityType.link ||
          (i < components.length - 1 &&
              type != FileSystemEntityType.directory &&
              type != FileSystemEntityType.notFound)) {
        throw const AppError(ErrorCode.unsafePath);
      }
    }
    return cursor;
  }

  void _checkNotLeased(String relative) {
    if (_leases.keys.any(
      (active) =>
          active == relative ||
          active.startsWith('$relative/') ||
          relative.startsWith('$active/'),
    )) {
      throw const AppError(ErrorCode.resourceInUse);
    }
  }

  @override
  Future<List<String>> stagingDirectories() => _exclusive(() async {
    final directory = await _resolve('staging');
    if (!await Directory(directory).exists()) return [];
    final ids = <String>[];
    await for (final entry in Directory(directory).list(followLinks: false)) {
      final id = p.basename(entry.path);
      final resolved = await _resolve('staging/$id');
      if (await FileSystemEntity.type(resolved, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw const AppError(ErrorCode.unsafePath);
      }
      ids.add(id);
    }
    return ids;
  });

  /// SQLite ouvre aussi des fichiers auxiliaires ; refuser leurs liens avant ouverture.
  Future<File> databaseFile() => _exclusive(() async {
    for (final suffix in ['', '-journal', '-wal', '-shm']) {
      await _resolve('prototype.sqlite$suffix');
    }
    return File(await _resolve('prototype.sqlite'));
  });

  /// Atomically publish a complete audio object inside the checked private root.
  Future<File> writeAudioCache(String key, List<int> bytes) =>
      _exclusive(() async {
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key) || bytes.length > 960044) {
          throw const AppError(ErrorCode.invalidContent);
        }
        final relative = 'cache/audio/$key.wav';
        _checkNotLeased(relative);
        final sidecar = File(await _resolve('cache/audio/$key.alignment.json'));
        if (await sidecar.exists()) await sidecar.delete();
        final target = await _resolve(relative);
        final staging = await _resolve('cache/audio/$key.part');
        await Directory(p.dirname(target)).create(recursive: true);
        await File(staging).writeAsBytes(bytes, flush: true);
        try {
          if (await File(target).exists()) await File(target).delete();
          final published = await File(staging).rename(target);
          final integrity = File(
            await _resolve('cache/audio/$key.integrity.json'),
          );
          final integrityPart = File(
            await _resolve('cache/audio/$key.integrity.part'),
          );
          try {
            await integrityPart.writeAsString(
              jsonEncode({
                'version': 1,
                'sha256': sha256.convert(bytes).toString(),
                'bytes': bytes.length,
              }),
              flush: true,
            );
            if (await integrity.exists()) await integrity.delete();
            await integrityPart.rename(integrity.path);
          } finally {
            if (await integrityPart.exists()) await integrityPart.delete();
          }
          return published;
        } finally {
          if (await File(staging).exists()) await File(staging).delete();
        }
      });

  /// Sidecar writes and WAV removal share the same lock and lease boundary.
  Future<void> writeAlignmentCache(
    String key,
    List<int> bytes,
    String wavSha,
  ) => _exclusive(() async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key) || bytes.length > 1048576) {
      throw const AppError(ErrorCode.invalidContent);
    }
    final wav = 'cache/audio/$key.wav';
    _checkNotLeased(wav);
    final file = File(await _resolve(wav));
    if (!await file.exists() ||
        await file.length() > 960044 ||
        (await sha256.bind(file.openRead()).first).toString() != wavSha) {
      throw const AppError(ErrorCode.invalidContent);
    }
    final target = File(await _resolve('cache/audio/$key.alignment.json'));
    final staging = File(await _resolve('cache/audio/$key.alignment.part'));
    try {
      await staging.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await staging.rename(target.path);
    } finally {
      if (await staging.exists()) await staging.delete();
    }
  });

  /// Evict complete unleased derived objects by age, including their sidecars.
  Future<List<String>> trimAudioCache({
    int maxBytes = 67108864,
    int maxObjects = 128,
  }) => _exclusive(() async {
    final directory = await _resolve('cache/audio');
    if (!await Directory(directory).exists()) return <String>[];
    final groups = <String, List<File>>{};
    for (final file in await _checkedFiles(directory)) {
      final match = RegExp(
        r'^([a-f0-9]{64})\.(?:wav|alignment\.json|alignment\.part|integrity\.json|integrity\.part|part)$',
      ).firstMatch(p.basename(file.path));
      if (match != null) groups.putIfAbsent(match[1]!, () => []).add(file);
    }
    final objects =
        <({String key, List<File> files, int size, DateTime time})>[];
    var bytes = 0;
    for (final entry in groups.entries) {
      var size = 0;
      var time = DateTime.fromMillisecondsSinceEpoch(0);
      for (final file in entry.value) {
        final stat = await file.stat();
        size += stat.size;
        if (stat.modified.isAfter(time)) time = stat.modified;
      }
      bytes += size;
      objects.add((key: entry.key, files: entry.value, size: size, time: time));
    }
    objects.sort((a, b) => a.time.compareTo(b.time));
    var count = objects.length;
    final removed = <String>[];
    for (final object in objects) {
      if (bytes <= maxBytes && count <= maxObjects) break;
      try {
        _checkNotLeased('cache/audio/${object.key}.wav');
      } on AppError catch (e) {
        if (e.code == ErrorCode.resourceInUse) continue;
        rethrow;
      }
      for (final file in object.files) {
        if (await file.exists()) await file.delete();
      }
      removed.add(object.key);
      bytes -= object.size;
      count--;
    }
    return removed;
  });
  Future<String?> audioCacheDigest(String key) => _exclusive(() async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw const AppError(ErrorCode.invalidContent);
    }
    final file = File(await _resolve('cache/audio/$key.integrity.json'));
    if (!await file.exists() || await file.length() > 1024) return null;
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is Map &&
          value['version'] == 1 &&
          value['sha256'] is String &&
          RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String)) {
        return value['sha256'] as String;
      }
    } on FormatException {
      return null;
    }
    return null;
  });
  Future<void> touchAudioCache(String key) => _exclusive(() async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw const AppError(ErrorCode.invalidContent);
    }
    await File(await _resolve('cache/audio/$key.wav'))
        .setLastModified(DateTime.now());
  });

  Future<List<int>?> readAlignmentCache(String key) => _exclusive(() async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw const AppError(ErrorCode.invalidContent);
    }
    final file = File(await _resolve('cache/audio/$key.alignment.json'));
    if (!await file.exists()) return null;
    if (await file.length() > 1048576) return null;
    return file.readAsBytes();
  });

  Future<void> deleteAudioObject(String key) => _exclusive(() async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw const AppError(ErrorCode.invalidContent);
    }
    _checkNotLeased('cache/audio/$key.wav');
    for (final suffix in [
      '.alignment.json',
      '.alignment.part',
      '.integrity.json',
      '.integrity.part',
      '.wav',
      '.part',
    ]) {
      final file = File(await _resolve('cache/audio/$key$suffix'));
      if (await file.exists()) await file.delete();
    }
  });

  Future<File> audioCacheFile(String key) => _exclusive(() async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
      throw const AppError(ErrorCode.invalidContent);
    }
    final path = await _resolve('cache/audio/$key.wav');
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const AppError(ErrorCode.storageUnavailable);
    }
    return File(path);
  });

  @override
  Future<bool> exists(String relative) => _exclusive(
    () async =>
        await FileSystemEntity.type(
          await _resolve(relative),
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound,
  );

  Future<void> writeStagedFile(
    String operationId,
    String relativeFile,
    List<int> bytes, {
    required int maxBytes,
  }) => _exclusive(() async {
    requireIdentifier(operationId);
    validateRelativePath(relativeFile);
    if (maxBytes < 0 || bytes.length > maxBytes) {
      throw const AppError(ErrorCode.storageLimitExceeded);
    }
    final relative = 'staging/$operationId/$relativeFile';
    _checkNotLeased(relative);
    final destination = await _resolve(relative);
    final temporary = await _resolve('$relative.part');
    if (await File(destination).exists()) {
      throw const AppError(ErrorCode.storageUnavailable);
    }
    await Directory(p.dirname(destination)).create(recursive: true);
    try {
      await File(temporary).writeAsBytes(bytes, flush: true);
      await File(temporary).rename(destination);
    } on FileSystemException {
      if (await File(temporary).exists()) await File(temporary).delete();
      throw const AppError(ErrorCode.storageUnavailable);
    }
  });

  Future<List<File>> _checkedFiles(String directory) async {
    final result = <File>[];
    await for (final entry in Directory(directory).list(followLinks: false)) {
      final relative = p
          .relative(entry.path, from: root.path)
          .split(p.separator)
          .join('/');
      final checked = await _resolve(relative);
      final type = await FileSystemEntity.type(checked, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        result.addAll(await _checkedFiles(checked));
      } else if (type == FileSystemEntityType.file) {
        result.add(File(checked));
      } else {
        throw const AppError(ErrorCode.unsafePath);
      }
    }
    return result;
  }

  Future<void> writeStagedStream(
    String operationId,
    String name,
    Stream<List<int>> chunks, {
    required int maxBytes,
  }) => _exclusive(() async {
    requireIdentifier(operationId);
    validateRelativePath(name);
    final relative = 'staging/$operationId/$name';
    final destination = await _resolve(relative);
    final temporary = await _resolve('$relative.part');
    if (await FileSystemEntity.type(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const AppError(ErrorCode.storageUnavailable);
    }
    await Directory(p.dirname(destination)).create(recursive: true);
    final output = await File(temporary).open(mode: FileMode.write);
    var count = 0;
    try {
      await for (final chunk in chunks) {
        count += chunk.length;
        if (count > maxBytes) {
          throw const AppError(ErrorCode.storageLimitExceeded);
        }
        await output.writeFrom(chunk);
      }
      if (count != maxBytes) {
        throw const AppError(ErrorCode.modelIntegrityFailed);
      }
      await output.flush();
    } finally {
      await output.close();
    }
    await File(temporary).rename(destination);
  });

  @override
  Future<bool> verify(String relative, List<BundleFile> expected) =>
      _exclusive(() async {
        final directory = await _resolve(relative);
        if (await FileSystemEntity.type(directory, followLinks: false) !=
            FileSystemEntityType.directory) {
          return false;
        }
        final files = await _checkedFiles(directory);
        if (files.length != expected.length) return false;
        for (final spec in expected) {
          final name = await _resolve('$relative/${spec.relativePath}');
          if (await FileSystemEntity.type(name, followLinks: false) !=
              FileSystemEntityType.file) {
            return false;
          }
          final file = File(name);
          if (await file.length() != spec.byteSize ||
              (await sha256.bind(file.openRead()).first).toString() !=
                  spec.sha256) {
            return false;
          }
        }
        return true;
      });

  @override
  Future<void> publish(String staging, String destination) =>
      _exclusive(() async {
        // Une publication ne peut pas transformer un répertoire arbitraire en modèle.
        if (!staging.startsWith('staging/') ||
            !destination.startsWith('models/')) {
          throw const AppError(ErrorCode.unsafePath);
        }
        _checkNotLeased(staging);
        _checkNotLeased(destination);
        final source = await _resolve(staging);
        final target = await _resolve(destination);
        if (await FileSystemEntity.type(source, followLinks: false) !=
                FileSystemEntityType.directory ||
            await FileSystemEntity.type(target, followLinks: false) !=
                FileSystemEntityType.notFound) {
          throw const AppError(ErrorCode.storageUnavailable);
        }
        await _checkedFiles(source);
        await Directory(p.dirname(target)).create(recursive: true);
        await Directory(source).rename(target);
      });

  Future<ResourceLease> acquire(String relative) => _exclusive(() async {
    final resolved = await _resolve(relative);
    if (await FileSystemEntity.type(resolved, followLinks: false) ==
        FileSystemEntityType.notFound) {
      throw const AppError(ErrorCode.storageUnavailable);
    }
    _leases[relative] = (_leases[relative] ?? 0) + 1;
    return ResourceLease(() {
      final remaining = (_leases[relative] ?? 1) - 1;
      if (remaining == 0) {
        _leases.remove(relative);
      } else {
        _leases[relative] = remaining;
      }
    });
  });

  @override
  Future<void> delete(String relative) => _exclusive(() async {
    if (!['staging/', 'models/', 'cache/'].any(relative.startsWith)) {
      throw const AppError(ErrorCode.unsafePath);
    }
    _checkNotLeased(relative);
    final resolved = await _resolve(relative);
    final type = await FileSystemEntity.type(resolved, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.directory) {
      await _checkedFiles(resolved);
      // _resolve vérifie le chemin absolu final dans la racine privée.
      await Directory(resolved).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await File(resolved).delete();
    } else {
      throw const AppError(ErrorCode.unsafePath);
    }
  });
}
