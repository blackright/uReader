import 'dart:typed_data';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'epub_package_parser.dart';
import 'epub_import_source.dart';
import 'request_identity.dart';

import 'package:flutter/services.dart';

import '../../domain/books.dart';
import '../../domain/app_error.dart' show requireIdentifier;
import 'epub_limits.dart';

class DocumentSelection {
  const DocumentSelection(this.handle, this.displayName, this.declaredBytes);
  final String handle;
  final String? displayName;
  final int? declaredBytes;
}

/// Process-local source ownership. Never logs names, URIs or platform exceptions.
class AndroidDocumentSource implements EpubImportSource {
  AndroidDocumentSource({MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('com.ureader.prototype/epub/v1');
  final MethodChannel _channel;
  String? _operation;
  int _generation = 0, _sequence = 0;
  final _clientId = newEpubClientId();
  bool _cancelled = false, _choosing = false;
  Future<void>? _cancellation;
  final _handles = <String, _SourceState>{};
  DocumentSelection? _selection;
  DocumentSelection? get selection => _selection;
  @override
  String? get displayName => _selection?.displayName;
  void _checkActive() {
    if (_cancelled) throw const BookFailure(BookError.cancelled);
  }

  Future<Map<Object?, Object?>> _call(
    String method,
    Map<String, Object?> payload,
  ) async {
    final op = _operation;
    final generation = _generation;
    if (op == null) throw const BookFailure(BookError.invalidContent);
    final request = 'epub-$_clientId-${++_sequence}';
    try {
      final raw = await _channel.invokeMethod<Object?>(method, {
        'protocolVersion': 1,
        'requestId': request,
        'operationId': op,
        'generation': generation,
        'payload': payload,
      });
      if (method != 'cancel') _checkActive();
      if (op != _operation || generation != _generation) {
        throw const BookFailure(BookError.cancelled);
      }
      if (raw is! Map ||
          raw['protocolVersion'] != 1 ||
          raw['requestId'] != request ||
          raw['operationId'] != op ||
          raw['generation'] != generation ||
          raw.containsKey('result') == raw.containsKey('error')) {
        throw const BookFailure(BookError.invalidContent);
      }
      if (raw['error'] case final Map error) {
        throw BookFailure(switch (error['code']) {
          'cancelled' => BookError.cancelled,
          'limitExceeded' => BookError.limitExceeded,
          'sourceUnavailable' => BookError.sourceUnavailable,
          'invalidArchive' => BookError.invalidArchive,
          'storageUnavailable' => BookError.storageUnavailable,
          'insufficientStorage' => BookError.insufficientStorage,
          'operationInProgress' => BookError.operationInProgress,
          'unsafeContent' => BookError.unsafeContent,
          _ => BookError.invalidContent,
        });
      }
      if (raw['result'] is! Map) {
        throw const BookFailure(BookError.invalidContent);
      }
      return Map<Object?, Object?>.from(raw['result'] as Map);
    } on PlatformException {
      throw const BookFailure(BookError.sourceUnavailable);
    } on MissingPluginException {
      throw const BookFailure(BookError.sourceUnavailable);
    }
  }

  @override
  Future<String?> choose(String operationId, int generation) async {
    requireIdentifier(operationId);
    if (generation < 1 || _choosing || _handles.values.any((h) => !h.closed)) {
      throw const BookFailure(BookError.invalidContent);
    }
    _operation = operationId;
    _generation = generation;
    _cancelled = false;
    _cancellation = null;
    _selection = null;
    _choosing = true;
    try {
      final result = await _call('chooseDocument', {});
      if (result['status'] == 'cancelled') return null;
      final handle = result['sourceHandle'],
          name = result['displayName'],
          size = result['declaredBytes'];
      if (result['status'] != 'selected' ||
          handle is! String ||
          handle.isEmpty ||
          handle.length > 256 ||
          _handles.containsKey(handle) ||
          name != null && (name is! String || name.length > 4096) ||
          size != null &&
              (size is! int || size < 0 || size > 0x7fffffffffffffff)) {
        throw const BookFailure(BookError.invalidContent);
      }
      _handles[handle] = _SourceState();
      _selection = DocumentSelection(handle, name as String?, size as int?);
      return handle;
    } finally {
      _choosing = false;
    }
  }

  @override
  Future<BookSourceChunk> read(String handle, {int maxBytes = 65536}) async {
    _checkActive();
    final state = _handles[handle];
    if (maxBytes < 1 || maxBytes > EpubLimits.sourceChunkBytes) {
      throw const BookFailure(BookError.limitExceeded);
    }
    if (state == null || state.closed || state.reading || state.failed) {
      throw const BookFailure(BookError.invalidContent);
    }
    if (state.eof) {
      return BookSourceChunk(
        bytes: Uint8List(0),
        eof: true,
        totalBytes: state.total,
      );
    }
    state.reading = true;
    try {
      final result = await _call('readSource', {
        'sourceHandle': handle,
        'maxBytes': maxBytes,
      });
      final bytes = result['bytes'],
          eof = result['eof'],
          total = result['totalBytes'];
      if (bytes is! Uint8List ||
          eof is! bool ||
          total is! int ||
          bytes.length > maxBytes ||
          total != state.total + bytes.length ||
          total > EpubLimits.sourceBytes ||
          bytes.isEmpty && !eof) {
        throw const BookFailure(BookError.invalidContent);
      }
      state.total = total;
      state.eof = eof;
      return BookSourceChunk(bytes: bytes, eof: eof, totalBytes: total);
    } catch (_) {
      state.failed = true;
      rethrow;
    } finally {
      state.reading = false;
    }
  }

  /// The native source stages these exact chunks in BookFileStore's namespace.
  /// Dart computes SHA incrementally; declared provider size is never a quota.
  @override
  Future<({String sha256, int bytes})> copyAndHash(
    String handle, {
    void Function(int bytes)? progress,
  }) async {
    final digestOutput = _DigestOutput();
    final hash = sha256.startChunkedConversion(digestOutput);
    var total = 0;
    var hashClosed = false;
    try {
      while (true) {
        final chunk = await read(handle);
        hash.add(chunk.bytes);
        total = chunk.totalBytes;
        progress?.call(total);
        if (chunk.eof) break;
      }
      hash.close();
      hashClosed = true;
      await close(handle);
      return (sha256: digestOutput.value!.toString(), bytes: total);
    } catch (_) {
      if (!hashClosed) hash.close();
      if (!_cancelled) await cancel(_operation!, _generation);
      rethrow;
    }
  }

  @override
  Future<AndroidEpubArchive> openArchive() async {
    final result = await _call('openArchive', {});
    final h = result['archiveHandle'], n = result['entryCount'];
    if (h is! String ||
        h.isEmpty ||
        n is! int ||
        n < 0 ||
        n > EpubLimits.entries) {
      throw const BookFailure(BookError.invalidContent);
    }
    final archive = AndroidEpubArchive._(this, h, n);
    await archive._loadIndex();
    return archive;
  }

  @override
  Future<void> close(String handle) async {
    final state = _handles[handle];
    if (state == null) throw const BookFailure(BookError.invalidContent);
    if (state.closed) return;
    if (_cancelled) {
      state.closed = true;
      return;
    }
    final result = await _call('close', {'handle': handle});
    if (result['closed'] != true) {
      throw const BookFailure(BookError.invalidContent);
    }
    state.closed = true;
  }

  @override
  Future<void> cancel(String operationId, int generation) {
    if (operationId != _operation || generation != _generation) {
      return Future.error(const BookFailure(BookError.invalidContent));
    }
    // Every caller must wait for native FD closure before touching staging.
    return _cancellation ??= _cancelNative();
  }

  Future<void> _cancelNative() async {
    _cancelled = true;
    _selection = null;
    final result = await _call('cancel', {});
    if (result['cancelled'] != true) {
      throw const BookFailure(BookError.invalidContent);
    }
    for (final h in _handles.values) {
      h.closed = true;
    }
  }
}

class _SourceState {
  int total = 0;
  bool eof = false, reading = false, closed = false, failed = false;
}

class _DigestOutput implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

class AndroidEpubArchive implements VerifiedEpubArchive {
  AndroidEpubArchive._(this.source, this.handle, this.entryCount);
  final AndroidDocumentSource source;
  final String handle;
  final int entryCount;
  final _entries = <String, String>{};
  final _verified = <String>{};
  final _metadataCache = <String, Uint8List>{};
  int _cacheBytes = 0;
  bool _closed = false, _reading = false, _failed = false;
  @override
  List<String> get names => List.unmodifiable(_entries.keys);
  Future<void> _loadIndex() async {
    String? cursor;
    final cursors = <String>{};
    while (true) {
      final result = await source._call('listEntries', {
        'archiveHandle': handle,
        'cursor': cursor,
        'pageSize': 128,
      });
      final rows = result['entries'],
          done = result['done'],
          next = result['nextCursor'];
      if (rows is! List ||
          rows.length > 128 ||
          done is! bool ||
          (next != null && next is! String) ||
          done != (next == null) ||
          !done && rows.isEmpty) {
        throw const BookFailure(BookError.invalidContent);
      }
      for (final row in rows) {
        if (row is! Map ||
            row['entryHandle'] is! String ||
            row['logicalName'] is! String ||
            row['compressedBytes'] is! int ||
            row['declaredBytes'] is! int ||
            row['directory'] is! bool) {
          throw const BookFailure(BookError.invalidContent);
        }
        final name = row['logicalName'] as String;
        if (utf8.encode(name).length > 1024 ||
            _entries.containsKey(name) ||
            _entries.values.contains(row['entryHandle']) ||
            _entries.length >= entryCount ||
            row['compressedBytes'] < 0 ||
            row['declaredBytes'] < 0) {
          throw const BookFailure(BookError.invalidContent);
        }
        _entries[name] = row['entryHandle'] as String;
      }
      if (done) break;
      if (!cursors.add(next as String)) {
        throw const BookFailure(BookError.invalidCursor);
      }
      cursor = next;
    }
    if (_entries.length != entryCount) {
      throw const BookFailure(BookError.invalidContent);
    }
  }

  @override
  Future<Uint8List> read(String name, {required int maxBytes}) async {
    if (maxBytes < 0 || maxBytes > EpubLimits.entryBytes) {
      throw const BookFailure(BookError.limitExceeded);
    }
    if (_closed || _failed) throw const BookFailure(BookError.invalidContent);
    final cached = _metadataCache[name];
    if (cached != null) {
      if (cached.length > maxBytes) {
        throw const BookFailure(BookError.limitExceeded);
      }
      return Uint8List.fromList(cached);
    }
    final builder = BytesBuilder(copy: false);
    await _drain(name, maxBytes, (chunk) => builder.add(chunk));
    final result = builder.takeBytes();
    if (maxBytes <= EpubLimits.metadataDocumentBytes &&
        _cacheBytes + result.length <= EpubLimits.metadataTotalBytes) {
      _metadataCache[name] = result;
      _cacheBytes += result.length;
    }
    return Uint8List.fromList(result);
  }

  Future<void> _drain(
    String name,
    int maxBytes,
    void Function(Uint8List) sink,
  ) async {
    if (_closed ||
        _failed ||
        _reading ||
        !_entries.containsKey(name) ||
        _verified.contains(name)) {
      throw const BookFailure(BookError.invalidContent);
    }
    _reading = true;
    var total = 0;
    try {
      while (true) {
        final result = await source._call('readEntry', {
          'archiveHandle': handle,
          'entryHandle': _entries[name],
          'maxBytes': 65536,
        });
        final bytes = result['bytes'],
            eof = result['eof'],
            sum = result['totalBytes'];
        if (bytes is! Uint8List ||
            bytes.length > 65536 ||
            eof is! bool ||
            sum is! int ||
            sum != total + bytes.length ||
            sum > maxBytes ||
            bytes.isEmpty && !eof) {
          throw const BookFailure(BookError.limitExceeded);
        }
        total = sum;
        sink(bytes);
        if (eof) break;
      }
      _verified.add(name);
    } catch (_) {
      _failed = true;
      rethrow;
    } finally {
      _reading = false;
    }
  }

  /// CRC/real-byte validation of every unused entry is mandatory before ready.
  @override
  Future<void> verifyRemaining() async {
    for (final name in names) {
      if (!_verified.contains(name)) {
        await _drain(name, EpubLimits.entryBytes, (_) {});
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    final result = await source._call('close', {'handle': handle});
    if (result['closed'] != true) {
      throw const BookFailure(BookError.invalidContent);
    }
    _closed = true;
    _metadataCache.clear();
  }
}
