import 'package:flutter/foundation.dart';

import '../../domain/books.dart';
import '../../infrastructure/database/book_repository.dart';

class LibraryQueryController extends ChangeNotifier {
  LibraryQueryController(this.repository, {required this.normalizeKey});
  final BookRepository repository;
  final Future<String> Function(String) normalizeKey;
  List<Book> books = [];
  BookFailure? error;
  bool loading = false, hasMore = true;
  BookSort sort = BookSort.recent;
  String searchText = '';
  bool get isDisposed => _disposed;
  String _search = '';
  String? _nextKey, _nextId;
  int _generation = 0;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh({String search = '', BookSort? sort}) async {
    searchText = search;
    if (sort != null) this.sort = sort;
    final generation = ++_generation;
    loading = true;
    error = null;
    books = [];
    _nextKey = null;
    _nextId = null;
    hasMore = true;
    _notify();
    try {
      final normalized = await normalizeKey(search);
      if (generation != _generation) return;
      _search = normalized;
      await _load(generation);
    } on BookFailure catch (e) {
      if (generation == _generation) error = e;
    } catch (_) {
      if (generation == _generation) {
        error = const BookFailure(BookError.storageUnavailable);
      }
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> nextPage() async {
    if (loading || !hasMore) return;
    loading = true;
    _notify();
    final generation = _generation;
    try {
      await _load(generation);
    } on BookFailure catch (e) {
      if (generation == _generation) error = e;
    } catch (_) {
      if (generation == _generation) {
        error = const BookFailure(BookError.storageUnavailable);
      }
    } finally {
      if (generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> _load(int generation) async {
    final page = await repository.page(
      search: _search,
      sort: sort,
      afterKey: _nextKey,
      afterId: _nextId,
    );
    if (generation != _generation || _disposed) return;
    books = List.unmodifiable([...books, ...page.books]);
    _nextKey = page.nextKey;
    _nextId = page.nextId;
    hasMore = _nextId != null;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
