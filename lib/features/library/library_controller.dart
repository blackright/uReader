import '../../domain/books.dart';
import '../../infrastructure/database/book_repository.dart';
import 'library_query_controller.dart';
import 'book_removal_service.dart';

class LibraryController extends LibraryQueryController {
  LibraryController(
    super.repository, {
    required super.normalizeKey,
    this.removal,
  });
  final BookRemovalService? removal;
  final removing = <String>{};
  final removalErrors = <String, BookFailure>{};
  final _removed = <ContentKey>{};
  List<Book> pendingRemovals = [];
  String? announcement;
  int _refreshIntent = 0;
  void _changed() {
    if (!isDisposed) notifyListeners();
  }

  bool canOpen(Book book) =>
      !_removed.contains(book.key) &&
      !removing.contains(book.key.id) &&
      !pendingRemovals.any((b) => b.key.id == book.key.id) &&
      !removalErrors.containsKey(book.key.id);
  @override
  Future<void> refresh({String search = '', BookSort? sort}) async {
    final intent = ++_refreshIntent;
    await super.refresh(search: search, sort: sort);
    if (isDisposed || intent != _refreshIntent) return;
    try {
      final pending = await repository.deletingPage();
      if (isDisposed || intent != _refreshIntent) return;
      pendingRemovals = pending;
      _changed();
    } catch (_) {
      if (!isDisposed && intent == _refreshIntent) {
        error = const BookFailure(BookError.storageUnavailable);
        _changed();
      }
    }
  }

  Future<bool> remove(Book book, {required bool confirmed}) async {
    if (!confirmed || removal == null || removing.contains(book.key.id)) {
      return false;
    }
    removing.add(book.key.id);
    removalErrors.remove(book.key.id);
    announcement = null;
    _changed();
    try {
      final done = await removal!.remove(book.key, confirmed: true);
      if (done) {
        _removed.add(book.key);
        announcement = 'Livre supprimé de la bibliothèque.';
        await refresh(search: searchText, sort: sort);
      }
      return done;
    } on BookFailure catch (e) {
      removalErrors[book.key.id] = e;
      announcement = 'Suppression incomplète. Vous pouvez réessayer.';
      return false;
    } catch (_) {
      removalErrors[book.key.id] = const BookFailure(
        BookError.storageUnavailable,
      );
      announcement = 'Suppression incomplète. Vous pouvez réessayer.';
      return false;
    } finally {
      removing.remove(book.key.id);
      _changed();
    }
  }
}
