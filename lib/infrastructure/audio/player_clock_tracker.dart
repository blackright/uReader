import '../../domain/content.dart';
import '../../domain/word_alignment.dart';

/// Identity fence only. Position is supplied by the player, never a stopwatch.
class PlayerClockTracker {
  SessionToken? _token;
  String? _segment, _sha;
  PlayerClockSample? current;
  void select(SessionToken token, String segmentId, String audioSha256) {
    if (!validAudioSha(audioSha256) || segmentId.isEmpty) {
      throw ArgumentError('Invalid audio identity');
    }
    _token = token;
    _segment = segmentId;
    _sha = audioSha256;
    current = null;
  }

  PlayerClockSample? update(
    SessionToken token,
    String segmentId,
    String audioSha256,
    Duration position,
    PlayerClockState state,
    int monotonicMicros, {
    bool seek = false,
  }) {
    if (_token?.matches(token) != true ||
        _segment != segmentId ||
        _sha != audioSha256 ||
        position.isNegative ||
        monotonicMicros < 0 ||
        monotonicMicros < (current?.monotonicMicros ?? 0)) {
      return null;
    }
    final previous = current;
    final frozen =
        !seek &&
        previous != null &&
        (state == PlayerClockState.buffering ||
            state == PlayerClockState.paused &&
                previous.state != PlayerClockState.playing);
    return current = PlayerClockSample(
      token: token,
      segmentId: segmentId,
      audioSha256: audioSha256,
      position: frozen ? previous.position : position,
      state: state,
      monotonicMicros: monotonicMicros,
    );
  }

  void stop() {
    _token = null;
    _segment = _sha = null;
    current = null;
  }
}
