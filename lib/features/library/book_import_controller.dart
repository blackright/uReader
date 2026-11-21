import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/books.dart';
import 'book_importer.dart';

class BookImportController extends ChangeNotifier {
  BookImportController(this.importer);
  final BookImporter importer;
  ImportProgress? progress;
  BookImportResult? result;
  BookFailure? error;
  bool _disposed = false, _running = false;
  int _generation = 0;
  String _id() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (_running || _disposed) return;
    _running = true;
    error = null;
    result = null;
    progress = const ImportProgress(ImportStep.choosing);
    _notify();
    final generation = ++_generation;
    try {
      result = await importer.importBook(
        _id(),
        _id(),
        generation,
        progress: (p) {
          if (generation == _generation) {
            progress = p;
            _notify();
          }
        },
      );
    } on BookFailure catch (e) {
      error = e;
    } finally {
      _running = false;
      _notify();
    }
  }

  Future<void> cancel() async {
    await importer.cancel();
  }

  bool get running => _running;
  @override
  void dispose() {
    _disposed = true;
    if (_running && progress?.canCancel == true) {
      importer.cancel();
    }
    super.dispose();
  }
}
