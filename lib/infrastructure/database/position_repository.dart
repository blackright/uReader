import '../../domain/content.dart';
import '../../domain/ports.dart';

/// All writes share a queue. Revisions advance only after a successful commit.
class PositionRepository {
  PositionRepository(this.store, {this.latestVisual});
  final PositionStore store;
  final Future<ResumePosition?> Function()? latestVisual;
  final _revisions = <String, int>{};
  Future<void> _tail = Future.value();
  int _pending = 0;
  int _lastSaveMs = 0;
  void _observe(ResumePosition? position) {
    final time = position?.updatedAt.millisecondsSinceEpoch ?? 0;
    if (time > _lastSaveMs) _lastSaveMs = time;
  }

  String _key(String id, ReadingMode mode) => '$id/${mode.name}';

  Future<ResumePosition?> read(DemoText text, ReadingMode mode) async {
    if (_pending > 0) await _tail;
    final position = await store.readPosition(text.id, mode);
    _observe(position);
    _revisions[_key(text.id, mode)] = position?.revision ?? 0;
    if (position != null) text.validate(position.locator);
    return position;
  }

  Future<ResumePosition?> save(
    DemoText text,
    Locator locator,
    ReadingMode mode, {
    bool Function()? isCurrent,
  }) {
    _pending++;
    final result = _tail.then((_) async {
      text.validate(locator);
      if (isCurrent != null && !isCurrent()) return null;
      final key = _key(text.id, mode);
      if (!_revisions.containsKey(key)) {
        final old = await store.readPosition(text.id, mode);
        _observe(old);
        _revisions[key] = old?.revision ?? 0;
      }
      if (isCurrent != null && !isCurrent()) return null;
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final timestamp = now > _lastSaveMs ? now : _lastSaveMs + 1;
      final saved = await store.savePosition(
        text,
        locator,
        mode,
        expectedRevision: _revisions[key]!,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
      );
      _observe(saved);
      _revisions[key] = saved.revision;
      return saved;
    });
    _tail = result.then<void>(
      (_) {
        _pending--;
      },
      onError: (Object _) {
        _pending--;
      },
    );
    return result;
  }

  Future<void> flush() => _pending == 0 ? Future.value() : _tail;
}
