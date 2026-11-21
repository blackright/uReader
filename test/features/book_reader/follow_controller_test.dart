import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/word_alignment.dart';
import 'package:prototype/features/book_reader/follow_controller.dart';

WordAlignment followFixture({String? audioSha, List<WordCue>? cues}) =>
    WordAlignment(
      audioSha256: audioSha ?? 'a' * 64,
      sourceSha256: 'b' * 64,
      preparedSha256: 'c' * 64,
      passageId: 'p',
      sourceStart: 0,
      sourceEnd: 14,
      samples: 9600,
      alignerVersion: 'attention-l3h9-v1',
      normalizerVersion: 'fr-numbers-v3',
      preparerVersion: 'prepared-map-v1',
      cues:
          cues ??
          [
            WordCue(0, 2400, SourceSpan(0, 7)),
            WordCue(4800, 7200, SourceSpan(8, 13)),
          ],
    );

void main() {
  final token = SessionToken('reader', 1);
  PlayerClockSample clock(
    int ms, {
    int tick = 1,
    PlayerClockState state = PlayerClockState.playing,
    String? sha,
    SessionToken? session,
    String segment = 'wav',
  }) => PlayerClockSample(
    token: session ?? token,
    segmentId: segment,
    audioSha256: sha ?? 'a' * 64,
    position: Duration(milliseconds: ms),
    state: state,
    monotonicMicros: tick,
  );
  FollowController ready() =>
      FollowController(wordAlignmentAvailable: true)
        ..select(token: token, segmentId: 'wav', alignment: followFixture());

  test('paragraph fallback follows actual playback without word timing and survives pause', () {
    final f = FollowController(paragraphFollowing: true);
    addTearDown(f.dispose);
    f.select(
      token: token,
      segmentId: 'wav',
      alignment: null,
      passageId: 'p',
      paragraph: SourceSpan(0, 14),
      playing: false,
    );
    expect(f.paragraphActive, isFalse);
    expect(f.canNavigate, isFalse);
    f.transport(true);
    expect(f.paragraphActive, isTrue);
    expect(f.canNavigate, isTrue);
    expect(f.active, isNull);
    expect(f.targetSpan!.start, 0);
    f.transport(false);
    expect(f.paragraphActive, isTrue);
    expect(f.canNavigate, isFalse);
    f.clear();
    expect(f.paragraphActive, isFalse);
  });
  test('no qualification means unavailable even with cues', () {
    final f = FollowController();
    addTearDown(f.dispose);
    f.select(token: token, segmentId: 'wav', alignment: followFixture());
    expect(f.sample(clock(0), layoutGeneration: 0), isFalse);
    expect(f.mode, FollowMode.unavailable);
    expect(f.active, isNull);
  });
  test('actual clock selects cues; gaps have no invented highlight', () {
    final f = ready();
    addTearDown(f.dispose);
    f.sample(clock(0), layoutGeneration: 0);
    expect(f.active!.start, 0);
    f.sample(clock(150, tick: 2), layoutGeneration: 0);
    expect(f.active, isNull);
    expect(f.durable!.start, 0);
    f.sample(clock(220, tick: 3), layoutGeneration: 0);
    expect(f.active!.start, 8);
  });
  test('pause/buffering freeze, stop removes active and preserves durable', () {
    final f = ready();
    addTearDown(f.dispose);
    f.sample(clock(10), layoutGeneration: 0);
    f.sample(
      clock(220, tick: 2, state: PlayerClockState.paused),
      layoutGeneration: 0,
    );
    expect(f.active!.start, 0);
    f.sample(
      clock(230, tick: 3, state: PlayerClockState.buffering),
      layoutGeneration: 0,
    );
    expect(f.active!.start, 0);
    f.sample(
      clock(250, tick: 4, state: PlayerClockState.stopped),
      layoutGeneration: 0,
    );
    expect(f.active, isNull);
    expect(f.durable!.start, 0);
  });
  test(
    'session, WAV, hash, monotonic timestamp and stale layout are fenced',
    () {
      final f = ready();
      addTearDown(f.dispose);
      for (final c in [
        clock(0, session: SessionToken('old', 1)),
        clock(0, sha: 'd' * 64),
        clock(0, segment: 'other'),
      ]) {
        expect(f.sample(c, layoutGeneration: 0), isFalse);
      }
      f.layoutChanged(2);
      expect(f.sample(clock(0), layoutGeneration: 1), isFalse);
      expect(f.sample(clock(0), layoutGeneration: 2), isTrue);
      expect(f.sample(clock(220), layoutGeneration: 2), isFalse);
      expect(f.active!.start, 0);
    },
  );
  test('user consultation suspends across segment changes; resume only changes policy', () {
    final f = ready();
    addTearDown(f.dispose);
    f.navigation(ReaderNavigationOrigin.audioFollow);
    expect(f.canNavigate, isTrue);
    f.navigation(ReaderNavigationOrigin.user);
    expect(f.mode, FollowMode.suspended);
    f.select(token: token, segmentId: 'next', alignment: null);
    f.select(token: token, segmentId: 'next', alignment: followFixture());
    expect(f.mode, FollowMode.suspended);
    f.resume();
    expect(f.canNavigate, isTrue);
  });
  test('off survives missing mappings and foreground return never resumes navigation', () {
    final f = ready();
    addTearDown(f.dispose);
    f.disable();
    f.select(token: token, segmentId: 'wav', alignment: null);
    expect(f.mode, FollowMode.off);
    f.resume();
    expect(f.mode, FollowMode.unavailable);
    f.select(token: token, segmentId: 'wav', alignment: followFixture());
    f.setForeground(false);
    f.setForeground(true);
    expect(f.mode, FollowMode.suspended);
    expect(f.canNavigate, isFalse);
  });
  test(
    'backward seek uses new player position rather than elapsed wall time',
    () {
      final f = ready();
      addTearDown(f.dispose);
      f.sample(clock(220), layoutGeneration: 0);
      expect(f.active!.start, 8);
      f.sample(clock(20, tick: 2), layoutGeneration: 0);
      expect(f.active!.start, 0);
    },
  );
  test('invalid overlap and out-of-bounds cues are rejected', () {
    expect(
      () => followFixture(
        cues: [
          WordCue(0, 5000, SourceSpan(0, 7)),
          WordCue(4000, 6000, SourceSpan(8, 13)),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => followFixture(cues: [WordCue(0, 10000, SourceSpan(0, 7))]),
      throwsArgumentError,
    );
  });
}
