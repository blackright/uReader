import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../book_reader/book_image_view.dart';

typedef CoverLoader = Future<ui.Image?> Function(
  ContentKey,
  String,
  bool Function(),
);

class _Waiter {
  _Waiter(this.cancelled);
  final bool Function() cancelled;
  final result = Completer<ui.Image?>();
}

class _CoverTask {
  _CoverTask(this.key, this.resource, this.id);
  final ContentKey key;
  final String resource, id;
  final waiters = <_Waiter>[];
  bool cancelled = false;
  bool get wanted => !cancelled && waiters.any((w) => !w.cancelled());
}

/// Owns original images; consumers receive clones. Pending and decoded work bounded.
class LibraryCoverCache {
  LibraryCoverCache(
    BookNavigationSource source, {
    CoverLoader? loader,
    this.maxEntries = 12,
    this.maxPending = 32,
  }) : assert(maxEntries > 0 && maxEntries <= 32),
       assert(maxPending > 0 && maxPending <= 64),
       _load = loader ?? BookImageDecoder(source, maxDimension: 384).load;
  final int maxEntries, maxPending;
  final CoverLoader _load;
  final _images = <String, ({ContentKey key, ui.Image image})>{};
  final _pending = <String, _CoverTask>{};
  final _queue = Queue<_CoverTask>();
  bool _running = false, _closed = false;
  int peakCached = 0, peakPending = 0;
  int get cached => _images.length;
  int get pending => _pending.length;
  Future<ui.Image?> load(
    ContentKey key,
    String resource,
    bool Function() cancelled,
  ) {
    if (_closed || cancelled()) return Future.value();
    final id = '${key.id}:${key.version}:$resource';
    final hit = _images.remove(id);
    if (hit != null) {
      _images[id] = hit;
      return Future.value(hit.image.clone());
    }
    _prune();
    var task = _pending[id];
    if (task == null) {
      if (_pending.length >= maxPending) return Future.value();
      task = _CoverTask(key, resource, id);
      _pending[id] = task;
      _queue.add(task);
    }
    final waiter = _Waiter(cancelled);
    task.waiters.add(waiter);
    if (_pending.length > peakPending) peakPending = _pending.length;
    if (!_running) unawaited(_drain());
    return waiter.result.future;
  }

  void _complete(_CoverTask task, ui.Image? image) {
    for (final w in task.waiters) {
      if (!w.result.isCompleted) {
        w.result.complete(!w.cancelled() && !_closed ? image?.clone() : null);
      }
    }
  }

  void _prune() {
    final obsolete = _queue.where((t) => !t.wanted).toList();
    for (final t in obsolete) {
      _queue.remove(t);
      if (identical(_pending[t.id], t)) _pending.remove(t.id);
      _complete(t, null);
    }
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (!_closed && _queue.isNotEmpty) {
        final task = _queue.removeFirst();
        ui.Image? image;
        try {
          if (task.wanted) {
            image = await _load(
              task.key,
              task.resource,
              () => _closed || !task.wanted,
            );
          }
        } catch (_) {
          image = null;
        }
        if (identical(_pending[task.id], task)) _pending.remove(task.id);
        if (_closed || !task.wanted) {
          image?.dispose();
          _complete(task, null);
          continue;
        }
        if (image != null) {
          _images[task.id] = (key: task.key, image: image);
          while (_images.length > maxEntries) {
            _images.remove(_images.keys.first)!.image.dispose();
          }
          if (_images.length > peakCached) peakCached = _images.length;
        }
        _complete(task, image);
      }
    } finally {
      _running = false;
    }
  }

  void retain(Set<ContentKey> keys) {
    for (final id in _images.keys.toList()) {
      if (!keys.contains(_images[id]!.key)) _images.remove(id)!.image.dispose();
    }
    for (final task in _pending.values.toList()) {
      if (!keys.contains(task.key)) {
        task.cancelled = true;
        if (identical(_pending[task.id], task)) _pending.remove(task.id);
        _complete(task, null);
      }
    }
    _prune();
  }

  void close() {
    _closed = true;
    for (final v in _images.values) {
      v.image.dispose();
    }
    _images.clear();
    for (final t in _pending.values) {
      t.cancelled = true;
      _complete(t, null);
    }
    _pending.clear();
    _queue.clear();
  }
}
