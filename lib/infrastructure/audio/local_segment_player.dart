import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:just_audio/just_audio.dart' as local;

import '../../domain/app_error.dart';
import '../../domain/content.dart';
import '../../domain/ports.dart';
import '../../domain/word_alignment.dart';
import '../files/audio_cache.dart';
import '../files/private_file_store.dart';
import 'player_clock_tracker.dart';

class _QueuedFile {
  _QueuedFile(this.handle, this.token, this.sha, this.lease, this.path);
  final String handle, sha, path;
  final SessionToken token;
  final ResourceLease lease;
  bool announced = false, completed = false;
}

/// One native playlist. Every queued WAV remains leased until retired or stopped.
class LocalSegmentPlayer implements BufferedAudioPlayer, PlayerClock {
  LocalSegmentPlayer(
    this.cache, {
    Duration clockPeriod = const Duration(milliseconds: 40),
  }) {
    if (clockPeriod.inMilliseconds < 20 || clockPeriod.inMilliseconds > 50) {
      throw ArgumentError('Clock cadence must be 20–50 ms');
    }
    _positions = _player
        .createPositionStream(minPeriod: clockPeriod, maxPeriod: clockPeriod)
        .listen((_) => _sync());
    _states = _player.playerStateStream.listen((_) => _sync());
    _sequence = _player.sequenceStateStream.listen((_) => _sync());
  }
  final AudioCache cache;
  final _player = local.AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );
  final _clock = PlayerClockTracker();
  final _clockEvents = StreamController<PlayerClockSample>.broadcast();
  final _events = StreamController<PlayerEvent>.broadcast();
  final _timestamps = Stopwatch()..start();
  final _queue = <_QueuedFile>[];
  _QueuedFile? _current;
  late final StreamSubscription<Duration> _positions;
  late final StreamSubscription<local.PlayerState> _states;
  late final StreamSubscription<local.SequenceState> _sequence;
  bool _resetting = false, _running = false;
  int _intent = 0;
  Future<void>? _disposal;
  @override
  Stream<PlayerEvent> get events => _events.stream;
  @override
  Stream<PlayerClockSample> get clockSamples => _clockEvents.stream;
  @override
  bool contains(SessionToken token) =>
      _queue.any((f) => f.token.matches(token));

  @override
  bool isCurrent(SessionToken token) {
    final tag = _player.sequenceState.currentSource?.tag;
    return tag is _QueuedFile && tag.token.matches(token);
  }

  void _finish(_QueuedFile entry) {
    if (!entry.completed) {
      entry.completed = true;
      _events.add(PlayerEvent(PlayerEventKind.completed, entry.token));
    }
  }

  void _sync() {
    if (_resetting || _disposal != null) return;
    final selected = _player.sequenceState.currentSource?.tag;
    if (selected is! _QueuedFile || !_queue.contains(selected)) return;
    if (_current != selected) {
      final old = _current;
      if (old != null && old.announced) _finish(old);
      _current = selected;
      _clock.select(selected.token, selected.handle, selected.sha);
    }
    final state = _player.playerState;
    final clockState = switch (state.processingState) {
      local.ProcessingState.loading ||
      local.ProcessingState.buffering => PlayerClockState.buffering,
      local.ProcessingState.completed ||
      local.ProcessingState.idle => PlayerClockState.stopped,
      _ => state.playing ? PlayerClockState.playing : PlayerClockState.paused,
    };
    final sample = _clock.update(
      selected.token,
      selected.handle,
      selected.sha,
      _player.position,
      clockState,
      _timestamps.elapsedMicroseconds,
    );
    if (sample != null) _clockEvents.add(sample);
    if (state.playing &&
        state.processingState == local.ProcessingState.ready &&
        !selected.announced) {
      selected.announced = true;
      _events.add(PlayerEvent(PlayerEventKind.started, selected.token));
    }
    if (state.processingState == local.ProcessingState.completed &&
        selected.announced) {
      _finish(selected);
    }
  }

  Future<_QueuedFile> _prepare(String handle, SessionToken token) async {
    final lease = await cache.files.acquire('cache/audio/$handle.wav');
    try {
      final file = await cache.files.audioCacheFile(handle);
      if (await file.length() > 960044 || await file.length() < 46) {
        throw const AppError(ErrorCode.invalidContent);
      }
      final digest = (await sha256.bind(file.openRead()).first).toString();
      return _QueuedFile(handle, token, digest, lease, file.path);
    } catch (_) {
      lease.release();
      rethrow;
    }
  }

  @override
  Future<void> open(String handle, SessionToken token) async {
    if (_disposal != null) throw const AppError(ErrorCode.engineUnavailable);
    final intent = ++_intent;
    await _reset();
    final entry = await _prepare(handle, token);
    if (intent != _intent || _disposal != null) {
      entry.lease.release();
      return;
    }
    _queue.add(entry);
    try {
      await _player.setAudioSources([
        local.AudioSource.file(entry.path, tag: entry),
      ]);
      if (intent == _intent) _sync();
    } catch (_) {
      _queue.remove(entry);
      entry.lease.release();
      rethrow;
    }
  }

  @override
  Future<void> append(String handle, SessionToken token) async {
    if (_disposal != null || _queue.isEmpty) {
      throw const AppError(ErrorCode.engineUnavailable);
    }
    if (contains(token)) return;
    if (_queue.length >= 16) throw const AppError(ErrorCode.resourceInUse);
    final intent = _intent;
    final entry = await _prepare(handle, token);
    if (intent != _intent || _disposal != null) {
      entry.lease.release();
      return;
    }
    _queue.add(entry);
    try {
      await _player.addAudioSource(
        local.AudioSource.file(entry.path, tag: entry),
      );
      if (intent != _intent) return;
      // A segment that arrived after a genuine underrun resumes at the next source,
      // never by replaying the completed file. Paused playback remains paused.
      if (_running &&
          _player.processingState == local.ProcessingState.completed) {
        await _player.seek(Duration.zero, index: _queue.indexOf(entry));
        if (intent == _intent) _start();
      }
      _sync();
    } catch (_) {
      // Keep the lease until reset if the native playlist may contain the source.
      rethrow;
    }
  }

  @override
  Future<void> retire(SessionToken token) async {
    final index = _queue.indexWhere((f) => f.token.matches(token));
    if (index < 0) return;
    final entry = _queue[index];
    if (entry == _current) return;
    await _player.removeAudioSourceAt(index);
    _queue.remove(entry);
    entry.lease.release();
  }

  void _start() {
    final intent = _intent, entry = _current;
    unawaited(
      _player.play().catchError((Object _) {
        if (intent == _intent && entry != null && _disposal == null) {
          _events.add(PlayerEvent(PlayerEventKind.interrupted, entry.token));
        }
      }),
    );
  }

  @override
  Future<void> play() async {
    if (_queue.isEmpty || _disposal != null) {
      throw const AppError(ErrorCode.engineUnavailable);
    }
    _running = true;
    _start();
  }

  @override
  Future<void> pause() async {
    _running = false;
    _current?.announced = false;
    await _player.pause();
    _sync();
  }

  @override
  Future<void> stop() async {
    ++_intent;
    await _reset();
  }

  Future<void> _reset() async {
    _resetting = true;
    _running = false;
    final last = _clock.current;
    if (last != null && !_clockEvents.isClosed) {
      _clockEvents.add(
        PlayerClockSample(
          token: last.token,
          segmentId: last.segmentId,
          audioSha256: last.audioSha256,
          position: last.position,
          state: PlayerClockState.stopped,
          monotonicMicros: _timestamps.elapsedMicroseconds,
        ),
      );
    }
    _clock.stop();
    _current = null;
    try {
      await _player.stop();
      await _player.clearAudioSources();
    } finally {
      for (final entry in _queue) {
        entry.lease.release();
      }
      _queue.clear();
      _resetting = false;
    }
  }

  @override
  Future<void> dispose() => _disposal ??= _close();
  Future<void> _close() async {
    await stop();
    await _states.cancel();
    await _positions.cancel();
    await _sequence.cancel();
    await _player.dispose();
    await _events.close();
    await _clockEvents.close();
    _timestamps.stop();
  }
}
