import 'package:flutter/foundation.dart';

import '../../domain/content.dart';
import '../../domain/word_alignment.dart';

enum FollowMode { following, suspended, off, unavailable }

enum ReaderNavigationOrigin { user, audioFollow }

/// Pure visual policy. Never owns audio transport or invokes a seek.
class FollowController extends ChangeNotifier {
  FollowController({
    this.wordAlignmentAvailable = false,
    this.paragraphFollowing = false,
    this.alignmentValidated = false,
  });
  final bool wordAlignmentAvailable, paragraphFollowing, alignmentValidated;
  String? _passage;
  SourceSpan? _paragraph;
  bool _playing = false, _everPlayed = false;
  String? _fallbackSha;
  FollowMode mode = FollowMode.unavailable;
  FollowMode _choice = FollowMode.following;
  WordAlignment? _alignment;
  SessionToken? _token;
  String? _segment;
  int _layout = 0, _lastTimestamp = -1;
  bool _foreground = true, _closed = false;
  SourceSpan? active, durable;
  String? durablePassageId;
  String? get passageId => _alignment?.passageId ?? _passage;
  bool get paragraphActive =>
      _everPlayed &&
      mode != FollowMode.off &&
      (_paragraph != null || active != null);
  SourceSpan? get targetSpan => active ?? (paragraphActive ? _paragraph : null);
  bool get _available =>
      (wordAlignmentAvailable && _alignment != null) ||
      (paragraphFollowing && _paragraph != null);
  void transport(bool playing) {
    if (_playing == playing) return;
    _playing = playing;
    if (playing) _everPlayed = true;
    _notify();
  }

  int get layoutGeneration => _layout;
  bool get canNavigate =>
      _available && _playing && _foreground && mode == FollowMode.following;
  String get message => switch (mode) {
    FollowMode.following =>
      _alignment == null
          ? 'Suivi du paragraphe actif'
          : alignmentValidated
          ? 'Suivi mot à mot actif'
          : 'Suivi mot à mot expérimental',
    FollowMode.suspended => 'Suivi suspendu pendant la consultation',
    FollowMode.off => 'Suivi désactivé',
    FollowMode.unavailable => 'Suivi mot à mot indisponible',
  };
  void _notify() {
    if (!_closed) notifyListeners();
  }

  void select({
    required SessionToken token,
    required String segmentId,
    required WordAlignment? alignment,
    String? passageId,
    SourceSpan? paragraph,
    bool playing = true,
  }) {
    final same = _token?.matches(token) == true && _segment == segmentId;
    final wasPlayed = _everPlayed;
    _token = token;
    _segment = segmentId;
    _alignment = alignment;
    _passage = passageId;
    _paragraph = paragraph;
    _playing = playing;
    _everPlayed = playing || (same && wasPlayed);
    _fallbackSha = null;
    _lastTimestamp = -1;
    active = null;
    mode = _choice == FollowMode.off
        ? FollowMode.off
        : !_available
        ? FollowMode.unavailable
        : _choice;
    _notify();
  }

  bool sample(PlayerClockSample sample, {required int layoutGeneration}) {
    final alignment = _alignment;
    if (_closed ||
        !_available ||
        _token?.matches(sample.token) != true ||
        _segment != sample.segmentId ||
        !validAudioSha(sample.audioSha256) ||
        (alignment != null && alignment.audioSha256 != sample.audioSha256) ||
        (alignment == null &&
            _fallbackSha != null &&
            _fallbackSha != sample.audioSha256) ||
        layoutGeneration != _layout ||
        sample.monotonicMicros <= _lastTimestamp) {
      return false;
    }
    _lastTimestamp = sample.monotonicMicros;
    if (sample.state == PlayerClockState.stopped) {
      stop();
      return false;
    }
    if (sample.state != PlayerClockState.playing) {
      transport(false);
      return false;
    }
    _fallbackSha ??= sample.audioSha256;
    transport(true);
    final next = alignment?.at(sample.position)?.source;
    if (next != null) {
      durable = next;
      durablePassageId = passageId;
    }
    if (active?.start == next?.start && active?.end == next?.end) return true;
    active = next;
    _notify();
    return true;
  }

  void layoutChanged(int generation) {
    if (_layout == generation) return;
    _layout = generation;
    _notify();
  }

  void navigation(ReaderNavigationOrigin origin) {
    if (origin == ReaderNavigationOrigin.user && _choice != FollowMode.off) {
      _choice = FollowMode.suspended;
      if (mode == FollowMode.following) mode = FollowMode.suspended;
      _notify();
    }
  }

  void setForeground(bool value) {
    _foreground = value;
    // Returning to the app must never jump to the audio automatically.
    if (!value && _choice != FollowMode.off) {
      _choice = FollowMode.suspended;
      if (mode == FollowMode.following) mode = FollowMode.suspended;
      _notify();
    }
  }

  void resume() {
    _choice = FollowMode.following;
    mode = _available ? FollowMode.following : FollowMode.unavailable;
    _notify();
  }

  void disable() {
    _choice = mode = FollowMode.off;
    _notify();
  }

  void stop() {
    clear();
  }

  void clear() {
    _alignment = null;
    _passage = null;
    _paragraph = null;
    _playing = false;
    _everPlayed = false;
    _fallbackSha = null;
    _token = null;
    _segment = null;
    active = null;
    if (mode != FollowMode.off) mode = FollowMode.unavailable;
    _notify();
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
