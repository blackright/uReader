import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/domain/content.dart';
import 'package:prototype/domain/word_alignment.dart';
import 'package:prototype/infrastructure/audio/player_clock_tracker.dart';

void main() {
  final a = SessionToken('a', 1), b = SessionToken('b', 1);
  test(
    'position comes from player; pause and buffering freeze, stop invalidates',
    () {
      final tracker = PlayerClockTracker();
      tracker.select(a, 'segment-a', 'a' * 64);
      expect(
        tracker
            .update(
              a,
              'segment-a',
              'a' * 64,
              const Duration(milliseconds: 100),
              PlayerClockState.playing,
              1,
            )!
            .position
            .inMilliseconds,
        100,
      );
      final paused = tracker.update(
        a,
        'segment-a',
        'a' * 64,
        const Duration(milliseconds: 120),
        PlayerClockState.paused,
        2,
      )!;
      expect(paused.position.inMilliseconds, 120);
      expect(
        tracker
            .update(
              a,
              'segment-a',
              'a' * 64,
              const Duration(milliseconds: 999),
              PlayerClockState.paused,
              3,
            )!
            .position
            .inMilliseconds,
        120,
      );
      expect(
        tracker
            .update(
              a,
              'segment-a',
              'a' * 64,
              const Duration(milliseconds: 500),
              PlayerClockState.buffering,
              4,
            )!
            .position
            .inMilliseconds,
        120,
      );
      expect(
        tracker
            .update(
              a,
              'segment-a',
              'a' * 64,
              const Duration(milliseconds: 140),
              PlayerClockState.playing,
              5,
            )!
            .position
            .inMilliseconds,
        140,
      );
      tracker.stop();
      expect(
        tracker.update(
          a,
          'segment-a',
          'a' * 64,
          Duration.zero,
          PlayerClockState.playing,
          6,
        ),
        isNull,
      );
    },
  );
  test(
    'changed WAV, old segment/token/hash/time rejected; seek is explicit',
    () {
      final tracker = PlayerClockTracker()..select(a, 'one', 'a' * 64);
      tracker.update(
        a,
        'one',
        'a' * 64,
        const Duration(seconds: 2),
        PlayerClockState.playing,
        10,
      );
      expect(
        tracker.update(
          a,
          'one',
          'a' * 64,
          Duration.zero,
          PlayerClockState.playing,
          9,
        ),
        isNull,
      );
      tracker.select(b, 'two', 'b' * 64);
      expect(
        tracker.update(
          a,
          'one',
          'a' * 64,
          Duration.zero,
          PlayerClockState.playing,
          11,
        ),
        isNull,
      );
      expect(
        tracker.update(
          b,
          'two',
          'a' * 64,
          Duration.zero,
          PlayerClockState.playing,
          12,
        ),
        isNull,
      );
      expect(
        tracker
            .update(
              b,
              'two',
              'b' * 64,
              const Duration(milliseconds: 50),
              PlayerClockState.paused,
              13,
              seek: true,
            )!
            .position
            .inMilliseconds,
        50,
      );
    },
  );
}
