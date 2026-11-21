import 'dart:async';

import '../../domain/books.dart';
import 'epub_limits.dart';
import 'epub_projection_worker.dart';

/// One instance per import; chapter-local safety limits never reset book totals.
class XhtmlProjector {
  XhtmlProjector(
    this.key, {
    bool Function()? cancelled,
    int initialElements = 0,
  }) : _cancelled = cancelled ?? (() => false),
       xmlElements = initialElements;
  final ContentKey key;
  final bool Function() _cancelled;
  final _clock = Stopwatch()..start();
  int xmlElements;
  int blocks = 0, units = 0, cssBytes = 0, selectors = 0, evaluations = 0;
  void _check() {
    if (_cancelled()) throw const BookFailure(BookError.cancelled);
    if (_clock.elapsed > EpubLimits.analysisDeadline) {
      throw const BookFailure(BookError.deadlineExceeded);
    }
  }

  Future<ProjectionResult> project(
    int chapter,
    String source, {
    List<String> styles = const [],
  }) async {
    _check();
    final job = EpubProjectionWorker.start(
      key: key,
      chapterOrdinal: chapter,
      xhtml: source,
      localStyles: styles,
    );
    final timer = Timer.periodic(const Duration(milliseconds: 25), (_) {
      if (_cancelled() || _clock.elapsed > EpubLimits.analysisDeadline) {
        unawaited(job.cancel());
      }
    });
    try {
      final result = await job.result;
      _check();
      blocks += result.blocks.length;
      units += result.blocks.fold<int>(0, (s, b) => s + b.text.length);
      xmlElements += result.usage['elements'] ?? 0;
      cssBytes += result.usage['cssBytes'] ?? 0;
      selectors += result.usage['selectors'] ?? 0;
      evaluations += result.usage['evaluations'] ?? 0;
      if (blocks > EpubLimits.blocks ||
          units > EpubLimits.canonicalUnits ||
          xmlElements > EpubLimits.xmlElements ||
          cssBytes > EpubLimits.cssTotalBytes ||
          selectors > EpubLimits.cssSelectors ||
          evaluations > EpubLimits.selectorEvaluations) {
        throw const BookFailure(BookError.limitExceeded);
      }
      return result;
    } finally {
      timer.cancel();
    }
  }
}
