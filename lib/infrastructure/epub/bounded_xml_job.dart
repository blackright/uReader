import 'dart:async';
import 'dart:isolate';

import '../../domain/books.dart';
import 'epub_limits.dart';

/// Heavy bounded import analysis runs outside UI and cannot outlive cancellation.
/// Only trusted static/top-level functions and bounded strings enter this worker.
abstract final class BoundedXmlJob {
  static Future<T> run<I extends Object, T>(
    I source,
    Future<T> Function(I) work, {
    bool Function()? cancelled,
  }) async {
    if (cancelled?.call() == true) {
      throw const BookFailure(BookError.cancelled);
    }
    final result = Completer<T>(),
        responses = ReceivePort(),
        errors = ReceivePort();
    Isolate? worker;
    bool stopping = false;
    Timer? deadline, poll;
    void close() {
      deadline?.cancel();
      poll?.cancel();
      responses.close();
      errors.close();
    }

    Future<void> stop(BookError code) async {
      if (stopping || result.isCompleted) {
        return;
      }
      stopping = true;
      deadline?.cancel();
      poll?.cancel();
      await Future<void>.delayed(EpubLimits.cancellationGrace);
      worker?.kill(priority: Isolate.immediate);
      if (!result.isCompleted) {
        result.completeError(BookFailure(code));
      }
      close();
    }

    responses.listen((Object? value) {
      if (stopping || result.isCompleted) {
        return;
      }
      if (value is BookError) {
        result.completeError(BookFailure(value));
      } else {
        try {
          result.complete(value as T);
        } catch (_) {
          result.completeError(const BookFailure(BookError.invalidContent));
        }
      }
      worker?.kill(priority: Isolate.immediate);
      close();
    });
    errors.listen((_) {
      if (!stopping && !result.isCompleted) {
        result.completeError(const BookFailure(BookError.invalidContent));
        close();
      }
    });
    deadline = Timer(
      EpubLimits.analysisDeadline,
      () => unawaited(stop(BookError.deadlineExceeded)),
    );
    poll = Timer.periodic(const Duration(milliseconds: 25), (_) {
      if (cancelled?.call() == true) {
        unawaited(stop(BookError.cancelled));
      }
    });
    Isolate.spawn(
      _entry,
      [responses.sendPort, work, source],
      onError: errors.sendPort,
      errorsAreFatal: true,
    ).then(
      (value) {
        worker = value;
        if (result.isCompleted) {
          value.kill(priority: Isolate.immediate);
        }
      },
      onError: (_) {
        if (!stopping && !result.isCompleted) {
          result.completeError(const BookFailure(BookError.invalidContent));
          close();
        }
      },
    );
    return result.future;
  }

  static Future<void> _entry(List<Object> args) async {
    final port = args[0] as SendPort;
    try {
      port.send(await Function.apply(args[1] as Function, [args[2]]));
    } on BookFailure catch (e) {
      port.send(e.code);
    } catch (_) {
      port.send(BookError.invalidContent);
    }
  }
}
