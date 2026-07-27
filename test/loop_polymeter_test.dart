// Per-track pattern length, wired into the engine.
//
// The audible claim: shortening one track makes it come round sooner than the
// others, so the groove keeps changing without anybody editing a note. The
// claim that protects everyone else: a groove where nothing is shortened must
// render exactly as it did before this existed.

import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/loop_track_length.dart';
import 'package:flutter_test/flutter_test.dart';

LoopEngine _engine() {
  final e = LoopEngine(tempoBpm: 120);
  e.enabled
    ..clear()
    ..addAll(['drums', 'bass']);
  return e;
}

void main() {
  group('the default is untouched', () {
    test('an ordinary groove renders byte-for-byte as before', () {
      // The safety property. Every track at full length must produce exactly
      // the bytes it always did, or this feature is a regression for the 99%
      // of grooves that never use it.
      final a = _engine().renderLoop();
      final b = _engine().renderLoop();
      expect(a, b);

      final e = _engine();
      final before = e.renderLoop();
      expect(
        e.setTrackSteps('bass', kPatternSteps),
        isTrue,
        reason: 'setting the full length is allowed',
      );
      expect(e.renderLoop(), before, reason: 'a no-op must be a no-op');
    });

    test('the loop is still 2 bars', () {
      expect(_engine().timing.bars, 2);
    });
  });

  group('shortening a track', () {
    test('lengthens the rendered loop so the seam never clips it', () {
      // 3 does not divide 16, so the buffer has to reach 48 steps (6 bars) for
      // both to land whole. Anything less restarts the short track mid-repeat.
      final e = _engine();
      e.setTrackSteps('bass', 3);
      expect(e.timing.bars, 6);
      expect(e.timing.totalSteps, 48);
    });

    test('a length that divides the grid leaves the loop alone', () {
      final e = _engine();
      e.setTrackSteps('bass', 4);
      expect(e.timing.bars, 2, reason: '4 already fits twice per bar');
    });

    test('it actually changes the audio', () {
      final plain = _engine().renderLoop();
      final e = _engine();
      e.setTrackSteps('bass', 3);
      final poly = e.renderLoop();
      expect(poly, isNot(plain));
      expect(
        poly.length,
        greaterThan(plain.length),
        reason: 'a 6-bar loop holds more audio than a 2-bar one',
      );
    });

    test('the two tracks come round at different times', () {
      // The point of the feature: over one rendered loop the shortened track
      // repeats more often than the untouched one.
      final e = _engine();
      e.setTrackSteps('bass', 3);
      expect(e.timing.totalSteps ~/ 3, 16, reason: 'bass repeats 16 times');
      expect(e.timing.totalSteps ~/ kPatternSteps, 3, reason: 'drums 3 times');
    });

    test('shortening drums works too, not just pitched tracks', () {
      final plain = _engine().renderLoop();
      final e = _engine();
      e.setTrackSteps('drums', 6);
      expect(e.renderLoop(), isNot(plain));
    });
  });

  group('the allowed set is enforced, not clamped', () {
    test('a value outside it is refused and changes nothing', () {
      // Quietly rounding 5 to 4 would be a lie about what is playing, and 5
      // would blow the buffer bound the curated set exists to guarantee.
      final e = _engine();
      final before = e.renderLoop();
      expect(e.setTrackSteps('bass', 5), isFalse);
      expect(e.trackSteps('bass'), kPatternSteps);
      expect(e.renderLoop(), before);
    });

    test('every allowed length is accepted and bounded', () {
      for (final len in kLoopTrackLengths) {
        final e = _engine();
        expect(e.setTrackSteps('bass', len), isTrue, reason: 'len $len');
        expect(e.timing.totalSteps, lessThanOrEqualTo(48), reason: 'len $len');
      }
    });
  });

  test('the stem cache does not serve a stale length', () {
    // The cache key had to grow a length component; without it the first
    // render would be handed back forever.
    final e = _engine();
    final a = e.renderLoop();
    e.setTrackSteps('bass', 3);
    final b = e.renderLoop();
    e.setTrackSteps('bass', kPatternSteps);
    final c = e.renderLoop();
    expect(b, isNot(a));
    expect(c, a, reason: 'going back must restore the original render');
  });
}
