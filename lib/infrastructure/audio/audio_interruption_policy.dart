import 'dart:async';

import 'package:audio_session/audio_session.dart';

import '../../features/listening/playback_coordinator.dart';

/// End-of-interruption never resumes speech. Only an explicit command may do so.
class AudioInterruptionPolicy {
  AudioInterruptionPolicy({
    required this.owner,
    required Stream<bool> interruptions,
    required Stream<void> noisy,
    this.setActive,
  }) {
    _interruptions = interruptions.listen((begin) {
      if (begin) unawaited(owner.pause());
    });
    _noisy = noisy.listen((_) => unawaited(owner.pause()));
    owner.addListener(_stateChanged);
  }

  final PlaybackCoordinator owner;
  final Future<bool> Function(bool)? setActive;
  Future<void> _focusTail = Future.value();
  bool _closed = false;
  late final StreamSubscription<bool> _interruptions;
  late final StreamSubscription<void> _noisy;

  static Future<AudioInterruptionPolicy> attach(
    PlaybackCoordinator owner,
    AudioSession session,
  ) async {
    await session.configure(const AudioSessionConfiguration.speech());
    return AudioInterruptionPolicy(
      owner: owner,
      interruptions: session.interruptionEventStream.map(
        (event) => event.begin,
      ),
      noisy: session.becomingNoisyEventStream,
      setActive: (active) => session.setActive(active),
    );
  }

  Future<bool> _focus(bool active) {
    final result = _focusTail.then((_) async {
      if (_closed && active) return false;
      return await setActive?.call(active) ?? true;
    });
    _focusTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<bool> acquireFocus() => _focus(true);

  void _stateChanged() {
    if (owner.state != PlaybackState.playing &&
        owner.state != PlaybackState.preparing) {
      unawaited(_focus(false).catchError((Object _) => false));
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    owner.removeListener(_stateChanged);
    await _interruptions.cancel();
    await _noisy.cancel();
    await _focus(false);
  }
}
