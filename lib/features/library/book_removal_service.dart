import '../../domain/books.dart';
import '../../domain/app_error.dart';
import '../../infrastructure/database/book_operation_repository.dart';
import '../../infrastructure/files/book_file_store.dart';
import '../../infrastructure/files/book_operation_reconciler.dart';

/// Confirmed operations are serialized; the deletion journal survives every error.
class BookRemovalService {
  BookRemovalService({
    required this.journal,
    required this.files,
    required this.reconciler,
    required this.releaseTarget,
  });
  final BookOperationRepository journal;
  final BookFileStore files;
  final BookOperationReconciler reconciler;
  final Future<void> Function(ContentKey) releaseTarget;
  Future<void>? _tail;
  bool _closed = false;
  Future<bool> remove(ContentKey key, {required bool confirmed}) {
    if (!confirmed) return Future.value(false);
    if (_closed) {
      return Future.error(const BookFailure(BookError.operationInProgress));
    }
    final task = (_tail ?? Future<void>.value()).then((_) async {
      BookOperation? op;
      try {
        op = await journal.beginDeletion(key);
        if (op == null) return true;
        await releaseTarget(key);
        await reconciler.finishDeletion(op);
        return true;
      } catch (e) {
        if (op != null) {
          try {
            await journal.failDeletion(op);
          } catch (_) {
            /* Retain the original failure and journal. */
          }
        }
        if (e is BookFailure) rethrow;
        throw BookFailure(
          e is AppError && e.code == ErrorCode.resourceInUse
              ? BookError.operationInProgress
              : BookError.storageUnavailable,
        );
      }
    });
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<void> close() async {
    _closed = true;
    await _tail;
  }
}
