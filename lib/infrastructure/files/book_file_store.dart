import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/app_error.dart';
import '../../domain/storage.dart' show validateRelativePath;
import '../epub/epub_limits.dart';
import 'private_file_store.dart' show PrivateFileStore, ResourceLease;

/// Separate namespace and queue: long imports never lock model/audio operations.
/// As with PrivateFileStore, a compromised host racing path checks is out of scope.
class BookFileStore {
  BookFileStore._(this.root);
  final Directory root;
  final _writing = <String>{};
  final _leases = <String, int>{};
  final _releaseWaiters = <String, Set<Completer<void>>>{};
  Future<void> _tail = Future.value();
  static Future<BookFileStore> open(Directory root) async =>
      BookFileStore._((await PrivateFileStore.open(root)).root);
  void _identifier(String value) {
    requireIdentifier(value);
    if (value.endsWith('.part')) throw const AppError(ErrorCode.unsafePath);
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<String> _checked(String relative) async {
    validateRelativePath(relative);
    final parts = relative.split('/');
    if (!['books', 'book-staging'].contains(parts.first) || parts.length < 2) {
      throw const AppError(ErrorCode.unsafePath);
    }
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const AppError(ErrorCode.unsafePath);
    }
    var cursor = root.path;
    for (var i = 0; i < parts.length; i++) {
      cursor = p.join(cursor, parts[i]);
      if (!p.isWithin(root.path, cursor)) {
        throw const AppError(ErrorCode.unsafePath);
      }
      final type = await FileSystemEntity.type(cursor, followLinks: false);
      if (type == FileSystemEntityType.link ||
          i < parts.length - 1 &&
              type != FileSystemEntityType.directory &&
              type != FileSystemEntityType.notFound) {
        throw const AppError(ErrorCode.unsafePath);
      }
    }
    return cursor;
  }

  Future<File> bookFile(String bookId, String fileId) async {
    _identifier(bookId);
    _identifier(fileId);
    return File(await _checked('books/$bookId/$fileId'));
  }

  Future<File> stagingFile(String operationId, String fileId) async {
    _identifier(operationId);
    _identifier(fileId);
    return File(await _checked('book-staging/$operationId/$fileId'));
  }

  Future<void> writeStaged(
    String operationId,
    String fileId,
    Stream<List<int>> chunks, {
    required int maxBytes,
    bool Function()? cancelled,
  }) async {
    _identifier(operationId);
    _identifier(fileId);
    if (maxBytes < 0 ||
        maxBytes >
            (fileId == 'source'
                ? EpubLimits.sourceBytes
                : EpubLimits.entryBytes)) {
      throw const AppError(ErrorCode.storageLimitExceeded);
    }
    if (!_writing.add(operationId)) {
      throw const AppError(ErrorCode.resourceInUse);
    }
    RandomAccessFile? output;
    String? temporary;
    var ownsTemporary = false;
    try {
      final relative = 'book-staging/$operationId/$fileId';
      final destination = await _checked(relative);
      temporary = await _checked('$relative.part');
      if (await FileSystemEntity.type(destination, followLinks: false) !=
              FileSystemEntityType.notFound ||
          await FileSystemEntity.type(temporary, followLinks: false) !=
              FileSystemEntityType.notFound) {
        throw const AppError(ErrorCode.storageUnavailable);
      }
      await Directory(p.dirname(destination)).create(recursive: true);
      await _checked('$relative.part');
      await File(temporary).create(exclusive: true);
      ownsTemporary = true;
      output = await File(temporary).open(mode: FileMode.writeOnly);
      var bytes = 0;
      await for (final chunk in chunks) {
        if (cancelled?.call() ?? false) {
          throw const AppError(ErrorCode.cancelled);
        }
        if (chunk.length > EpubLimits.sourceChunkBytes ||
            bytes + chunk.length > maxBytes) {
          throw const AppError(ErrorCode.storageLimitExceeded);
        }
        await _checked('$relative.part');
        await output.writeFrom(chunk);
        bytes += chunk.length;
      }
      if (cancelled?.call() ?? false) throw const AppError(ErrorCode.cancelled);
      await output.flush();
      await output.close();
      output = null;
      await _checked(relative);
      await _checked('$relative.part');
      if (await FileSystemEntity.type(destination, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const AppError(ErrorCode.storageUnavailable);
      }
      await File(temporary).rename(destination);
      ownsTemporary = false;
    } finally {
      try {
        await output?.close();
      } finally {
        try {
          if (ownsTemporary &&
              temporary != null &&
              p.isWithin(root.path, temporary)) {
            final relative = p
                .relative(temporary, from: root.path)
                .split(p.separator)
                .join('/');
            await _checked(relative);
            if (await FileSystemEntity.type(temporary, followLinks: false) ==
                FileSystemEntityType.file) {
              await File(temporary).delete();
            }
          }
        } finally {
          _writing.remove(operationId);
        }
      }
    }
  }

  Future<void> publish(String operationId, String bookId) =>
      _exclusive(() async {
        _identifier(operationId);
        _identifier(bookId);
        if (_writing.contains(operationId) || (_leases[bookId] ?? 0) > 0) {
          throw const AppError(ErrorCode.resourceInUse);
        }
        final source = await _checked('book-staging/$operationId');
        final destination = await _checked('books/$bookId');
        if (await FileSystemEntity.type(source, followLinks: false) !=
                FileSystemEntityType.directory ||
            await FileSystemEntity.type(destination, followLinks: false) !=
                FileSystemEntityType.notFound) {
          throw const AppError(ErrorCode.storageUnavailable);
        }
        await _validateTree(source);
        await Directory(p.dirname(destination)).create(recursive: true);
        await _checked('books/$bookId');
        await Directory(source).rename(destination);
      });
  Future<ResourceLease> acquire(String bookId) => _exclusive(() async {
    _identifier(bookId);
    final directory = await _checked('books/$bookId');
    if (await FileSystemEntity.type(directory, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const AppError(ErrorCode.storageUnavailable);
    }
    _leases[bookId] = (_leases[bookId] ?? 0) + 1;
    return ResourceLease(() {
      final count = (_leases[bookId] ?? 1) - 1;
      if (count == 0) {
        _leases.remove(bookId);
        for (final waiter
            in _releaseWaiters.remove(bookId) ?? <Completer<void>>{}) {
          waiter.complete();
        }
      } else {
        _leases[bookId] = count;
      }
    });
  });
  Future<void> _validateTree(String absolute) async {
    if (!p.isWithin(root.path, absolute)) {
      throw const AppError(ErrorCode.unsafePath);
    }
    await for (final item in Directory(absolute).list(followLinks: false)) {
      final relative = p
          .relative(item.path, from: root.path)
          .split(p.separator)
          .join('/');
      final path = await _checked(relative);
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await _validateTree(path);
      } else if (type != FileSystemEntityType.file) {
        throw const AppError(ErrorCode.unsafePath);
      }
    }
  }

  Future<void> waitForRelease(
    String bookId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final waiter = await _exclusive(() async {
      _identifier(bookId);
      if ((_leases[bookId] ?? 0) == 0) return null;
      final waiter = Completer<void>();
      (_releaseWaiters[bookId] ??= {}).add(waiter);
      return waiter;
    });
    if (waiter == null) return;
    try {
      await waiter.future.timeout(timeout);
    } on TimeoutException {
      throw const AppError(ErrorCode.resourceInUse);
    } finally {
      _releaseWaiters[bookId]?.remove(waiter);
    }
  }

  Future<void> _remove(String relative) async {
    final path = await _checked(relative);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory) {
      throw const AppError(ErrorCode.unsafePath);
    }
    await _validateTree(path);
    // Checked absolute target is a strict descendant of the selected namespace.
    final domain = p.join(root.path, relative.split('/').first);
    if (!p.isWithin(domain, path)) throw const AppError(ErrorCode.unsafePath);
    await Directory(path).delete(recursive: true);
  }

  Future<void> removeStaging(String operationId) => _exclusive(() async {
    _identifier(operationId);
    if (_writing.contains(operationId)) {
      throw const AppError(ErrorCode.resourceInUse);
    }
    await _remove('book-staging/$operationId');
  });
  Future<void> removeBook(String bookId) => _exclusive(() async {
    _identifier(bookId);
    if ((_leases[bookId] ?? 0) > 0) {
      throw const AppError(ErrorCode.resourceInUse);
    }
    await _remove('books/$bookId');
  });
}
