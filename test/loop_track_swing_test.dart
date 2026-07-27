// L6 — per-track swing.
//
// Swing was one number for the whole groove. A swung hat over a straight bass
// is how a groove gets a human feel, and it is the last thing on this screen
// that a sequencer player would reach for and not find.
//
// The load-bearing property is NOT that it sounds different — it is that stems
// stay aligned. `boundaryMs` delays only ODD steps and a loop spans an even
// number of them, so swing cannot move the final boundary. If that ever stops
// being true, per-track swing has to go, because stems of different lengths
// would drift apart and the seam would click.

import 'package:comet_beat/core/audio/loop_engine.dart';
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
    test('a track reports the global swing until given its own', () {
      final e = _engine()..swing = 0.3;
      expect(e.trackSwing('drums'), 0.3);
      expect(e.trackSwing('bass'), 0.3);
    });

    test('setting a track to the global value renders identically', () {
      final a = _engine()..swing = 0.2;
      final before = a.renderLoop();
      a.setTrackSwing('bass', 0.2);
      expect(a.renderLoop(), before);
    });

    test('clearing it returns to the global value', () {
      final e = _engine()..swing = 0.2;
      final before = e.renderLoop();
      e.setTrackSwing('drums', 0.5);
      expect(e.renderLoop(), isNot(before));
      e.setTrackSwing('drums', null);
      expect(e.trackSwing('drums'), 0.2);
      expect(e.renderLoop(), before, reason: 'back to exactly the old render');
    });

    test('a track that plays only on the beat is unaffected by swing', () {
      // Not a gap — swing delays ODD eighth-steps, so a part sitting on the
      // downbeats has nothing to delay. Worth pinning: it is the reason a
      // change here can be inaudible, and the first thing to suspect before
      // concluding the feature is broken. (It briefly fooled me: I wrote these
      // tests against the bass and read "no change" as a bug.)
      final e = _engine();
      final before = e.renderLoop();
      e.setTrackSwing('bass', 0.6);
      expect(e.renderLoop(), before);
    });
  });

  group('one track can swing alone', () {
    test('it changes the audio', () {
      final plain = _engine().renderLoop();
      final e = _engine();
      e.setTrackSwing('drums', 0.5);
      expect(e.renderLoop(), isNot(plain));
    });

    test('THE INVARIANT: swing never changes the loop length', () {
      // Stems must stay aligned. A swung stem that ended a sample late would
      // drift against the others and click at the seam.
      final plain = _engine().renderLoop();
      for (final swing in [0.1, 0.3, 0.5, 0.6]) {
        final e = _engine();
        e.setTrackSwing('drums', swing);
        expect(
          e.renderLoop().length,
          plain.length,
          reason: 'swing $swing changed the rendered length',
        );
      }
    });

    test('it holds with a shortened track too (polymeter + swing)', () {
      // The two features that both touch the step grid, together.
      final e = _engine();
      e.setTrackSteps('drums', 3);
      final lengthOnly = e.renderLoop().length;
      e.setTrackSwing('drums', 0.5);
      expect(e.renderLoop().length, lengthOnly);
    });
  });

  group('the value is clamped, like the global one', () {
    test('out-of-range values are pulled into 0..0.6', () {
      final e = _engine();
      e.setTrackSwing('bass', 5);
      expect(e.trackSwing('bass'), 0.6);
      e.setTrackSwing('bass', -1);
      expect(e.trackSwing('bass'), 0.0);
    });
  });

  test('the stem cache does not serve a stale swing', () {
    // Drums, not bass: the bass sits on the beat, so its render would not move
    // and the test could not tell a working cache from a stale one.
    final e = _engine();
    final a = e.renderLoop();
    e.setTrackSwing('drums', 0.5);
    final b = e.renderLoop();
    e.setTrackSwing('drums', null);
    expect(b, isNot(a));
    expect(e.renderLoop(), a, reason: 'going back must restore the original');
  });
}
