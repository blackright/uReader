import '../../domain/paragraph_index.dart';

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../domain/books.dart';
import '../../domain/ports.dart';
import '../../domain/word_alignment.dart';
import '../listening/playback_coordinator.dart';
import '../listening/prepared_text_map.dart';
import '../listening/french_text_normalizer.dart';
import 'follow_controller.dart';

/// Optional bridge; owns no audio transport and retains only the current alignment.
class BookFollowBinding {
  BookFollowBinding({
    required this.key,
    required this.playback,
    required this.follow,
    this.loadAlignment,
  }) {
    playback.addListener(_changed);
    final player = playback.player;
    if (player is PlayerClock) {
      _clock = (player as PlayerClock).clockSamples.listen(_sample);
    }
    _changed();
  }
  final ContentKey key;
  final PlaybackCoordinator playback;
  final FollowController follow;
  final Future<WordAlignment?> Function(String)? loadAlignment;
  StreamSubscription<PlayerClockSample>? _clock;
  Future<void> _work = Future.value();
  String? _identity;
  int _intent = 0;
  bool _closed = false;
  void _changed() {
    if (_closed) return;
    if (playback.bookKey != key ||
        [
          PlaybackState.stopped,
          PlaybackState.completed,
          PlaybackState.error,
        ].contains(playback.state)) {
      if (_identity != null) {
        _identity = null;
        ++_intent;
        follow.clear();
      }
      return;
    }
    final output = playback.activeOutput, segment = playback.activeSegment;
    if (output == null || segment == null) return;
    final token = playback.activePlayerToken;
    final identity =
        '${token.sessionId}:${token.generation}:${output.audioHandle}';
    if (identity == _identity) {
      follow.transport(playback.state == PlaybackState.playing);
      return;
    }
    _identity = identity;
    final intent = ++_intent;
    follow.select(
      token: token,
      segmentId: output.audioHandle,
      alignment: null,
      passageId: segment.start.passageId,
      paragraph: SourceSpan(segment.start.offsetUtf16, segment.end.offsetUtf16),
      playing: playback.state == PlaybackState.playing,
    );
    if (!follow.wordAlignmentAvailable || loadAlignment == null) return;
    _work = _work
        .then((_) async {
          if (_closed || intent != _intent) return;
          WordAlignment? value;
          try {
            value = await loadAlignment!(output.audioHandle);
          } catch (_) {
            value = null;
          }
          if (_closed ||
              intent != _intent ||
              playback.bookKey != key ||
              !playback.activePlayerToken.matches(token) ||
              playback.activeOutput != output) {
            return;
          }
          if (value != null &&
              (value.passageId != segment.start.passageId ||
                  value.sourceStart != segment.start.offsetUtf16 ||
                  value.sourceEnd != segment.end.offsetUtf16 ||
                  value.sourceSha256 !=
                      sha256.convert(utf8.encode(segment.source)).toString() ||
                  value.preparedSha256 !=
                      sha256
                          .convert(utf8.encode(segment.synthesis))
                          .toString() ||
                  value.normalizerVersion != FrenchTextNormalizer.version ||
                  value.preparerVersion != PreparedTextMap.version ||
                  value.alignerVersion != 'attention-l3h9-v1')) {
            value = null;
          }
          if (value != null) {
            final boundaries = ParagraphIndex();
            final mapping =
                segment.preparedMap ??
                PreparedTextMap.fromSource(
                  segment.source,
                  sourceOffset: segment.start.offsetUtf16,
                );
            final expected = mapping.wordSources
                .map((r) => '${r.start}:${r.end}')
                .toSet();
            final observed = value.cues
                .map((c) => '${c.source.start}:${c.source.end}')
                .toSet();
            if (mapping.prepared != segment.synthesis ||
                expected.difference(observed).isNotEmpty) {
              value = null;
            }
            if (value == null) {
              follow.select(
                token: token,
                segmentId: output.audioHandle,
                alignment: null,
                passageId: segment.start.passageId,
                paragraph: SourceSpan(
                  segment.start.offsetUtf16,
                  segment.end.offsetUtf16,
                ),
                playing: playback.state == PlaybackState.playing,
              );
              return;
            }
            if (value.cues.any(
              (cue) =>
                  !boundaries.validTextBoundary(
                    segment.source,
                    cue.source.start - segment.start.offsetUtf16,
                  ) ||
                  !boundaries.validTextBoundary(
                    segment.source,
                    cue.source.end - segment.start.offsetUtf16,
                  ),
            )) {
              value = null;
            }
          }
          follow.select(
            token: token,
            segmentId: output.audioHandle,
            alignment: value,
            passageId: segment.start.passageId,
            paragraph: SourceSpan(
              segment.start.offsetUtf16,
              segment.end.offsetUtf16,
            ),
            playing: playback.state == PlaybackState.playing,
          );
        })
        .catchError((Object _) {
          if (!_closed && intent == _intent) {
            follow.select(
              token: token,
              segmentId: output.audioHandle,
              alignment: null,
              passageId: segment.start.passageId,
              paragraph: SourceSpan(
                segment.start.offsetUtf16,
                segment.end.offsetUtf16,
              ),
              playing: playback.state == PlaybackState.playing,
            );
          }
        });
  }

  void _sample(PlayerClockSample sample) {
    if (_closed ||
        playback.bookKey != key ||
        !playback.activePlayerToken.matches(sample.token)) {
      return;
    }
    final accepted = follow.sample(
      sample,
      layoutGeneration: follow.layoutGeneration,
    );
    if (accepted &&
        sample.state == PlayerClockState.playing &&
        follow.active != null) {
      playback.recordAlignedPosition(sample, follow.active!);
    }
  }

  Future<void> close() async {
    _closed = true;
    ++_intent;
    playback.removeListener(_changed);
    await _clock?.cancel();
    await _work;
  }
}
