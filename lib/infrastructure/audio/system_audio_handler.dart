import 'package:audio_service/audio_service.dart' as system;

import '../../features/listening/playback_coordinator.dart';

/// Adapter only: the coordinator remains the sole owner of inference and player.
class SystemAudioHandler extends system.BaseAudioHandler {
  SystemAudioHandler(this.owner) {
    owner.addListener(_publish);
    _publish();
  }

  final PlaybackCoordinator owner;
  bool _closed = false;

  void _publish() {
    if (_closed) return;
    final state = owner.state;
    final active =
        state == PlaybackState.playing || state == PlaybackState.preparing;
    final idle =
        state == PlaybackState.stopped ||
        state == PlaybackState.completed ||
        state == PlaybackState.error;
    if (owner.textId != null) {
      mediaItem.add(
        system.MediaItem(
          id: owner.textId!,
          title: owner.mediaTitle ?? 'Lecture française',
          artist: owner.mediaAuthor,
          album: owner.mediaChapter ?? 'uReader',
          // Total duration is unknown while speech is generated incrementally.
        ),
      );
    } else {
      mediaItem.add(null);
    }
    playbackState.add(
      system.PlaybackState(
        controls: idle
            ? []
            : [
                if (owner.bookKey != null) system.MediaControl.skipToPrevious,
                active ? system.MediaControl.pause : system.MediaControl.play,
                if (owner.bookKey != null) system.MediaControl.skipToNext,
                system.MediaControl.stop,
              ],
        androidCompactActionIndices: idle
            ? []
            : owner.bookKey == null
            ? [0, 1]
            : [0, 1, 2],
        processingState: switch (state) {
          PlaybackState.preparing => system.AudioProcessingState.buffering,
          PlaybackState.playing ||
          PlaybackState.paused => system.AudioProcessingState.ready,
          _ => system.AudioProcessingState.idle,
        },
        playing: active,
      ),
    );
  }

  @override
  Future<void> skipToPrevious() => owner.previous();
  @override
  Future<void> skipToNext() => owner.next();
  @override
  Future<void> play() {
    final context = owner.bookContext, target = owner.targetLocator;
    if (context != null &&
        target != null &&
        owner.state == PlaybackState.stopped) {
      return owner.playFromParagraph(context, target);
    }
    return owner.resume();
  }

  @override
  Future<void> pause() => owner.pause();
  @override
  Future<void> stop() {
    // audio_service may route native idle-service cleanup back through stop.
    // Preserve the terminal reason for the UI instead of hiding an error/end.
    if (owner.state == PlaybackState.error ||
        owner.state == PlaybackState.completed) {
      return Future.value();
    }
    return owner.stop();
  }

  @override
  Future<void> onTaskRemoved() => stop();
  @override
  Future<void> onNotificationDeleted() => stop();

  Future<void> close() async {
    if (_closed) return;
    await stop();
    owner.removeListener(_publish);
    _closed = true;
  }
}
