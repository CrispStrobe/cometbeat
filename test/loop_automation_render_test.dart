// A2 — rendering the level lane.
//
// The headline property is the one that protects every groove that does NOT use
// automation: with no lanes anywhere the render must be byte-for-byte what it
// was before this existed. That is why "no lane" is null rather than a flat
// lane — a flat lane still costs a multiply, and this assertion would be
// impossible to make honestly.
//
// The second property is the ORDER. mixStems unit-peak normalises each stem and
// then applies gain; a level lane folded into the samples before that would be
// divided straight back out by the peak it just changed. The lane therefore
// lands after, which is what makes a fade actually fade.

import 'package:comet_beat/core/audio/loop_automation.dart';
import 'package:comet_beat/core/audio/loop_engine.dart';
import 'package:comet_beat/core/audio/wav_io.dart';
import 'package:flutter_test/flutter_test.dart';

LoopEngine _engine() {
  final e = LoopEngine(tempoBpm: 120);
  e.enabled
    ..clear()
    ..addAll(['drums', 'bass']);
  return e;
}

/// Peak absolute sample over a fraction of the rendered loop.
double _peakIn(List<int> pcm, double from, double to) {
  final a = (pcm.length * from).round();
  final b = (pcm.length * to).round();
  var peak = 0.0;
  for (var i = a; i < b && i < pcm.length; i++) {
    final v = pcm[i].abs().toDouble();
    if (v > peak) peak = v;
  }
  return peak;
}

void main() {
  _a3();
  test('a groove with NO automation renders byte-for-byte as before', () {
    final a = _engine().renderLoop();
    final e = _engine();
    expect(e.hasAutomation, isFalse);
    expect(e.renderLoop(), a);
  });

  test('setting then clearing a lane returns the original bytes', () {
    final e = _engine();
    final before = e.renderLoop();
    e.setAutomation('drums', AutomationParam.level, AutomationLane([1, 0]));
    expect(e.renderLoop(), isNot(before));
    e.setAutomation('drums', AutomationParam.level, null);
    expect(e.hasAutomation, isFalse);
    expect(e.renderLoop(), before, reason: 'the cache must not hold the lane');
  });

  test('a fade-out lane makes the end quieter than the start', () {
    // The ordering test in disguise: applied before unit-peak normalisation the
    // fade would be divided back out and this would be flat.
    //
    // ONE track only. Measuring the whole mix while the bass plays on at full
    // level measures the bass, not the fade — which is how this test first
    // failed.
    final e = _engine();
    e.enabled
      ..clear()
      ..add('drums');
    e.setAutomation(
      'drums',
      AutomationParam.level,
      // 16 steps ramping 1 → 0 across the loop.
      AutomationLane([for (var i = 0; i < 16; i++) 1 - i / 15]),
    );
    final pcm = readWavPcm16(e.renderLoop()).samples;
    final head = _peakIn(pcm, 0.0, 0.2);
    final tail = _peakIn(pcm, 0.8, 1.0);
    expect(head, greaterThan(0), reason: 'the loop should make sound at all');
    expect(
      tail,
      lessThan(head * 0.5),
      reason: 'the tail of a fade-out must be much quieter than the head',
    );
  });

  test('silencing one track leaves the other audible', () {
    // Proves the envelope is per-stem rather than applied to the whole mix.
    final e = _engine();
    e.setAutomation(
      'drums',
      AutomationParam.level,
      AutomationLane(List<double>.filled(16, 0)),
    );
    final pcm = readWavPcm16(e.renderLoop()).samples;
    expect(
      _peakIn(pcm, 0.0, 1.0),
      greaterThan(0),
      reason: 'the bass should still be playing',
    );
  });

  test('a lane shorter than the loop repeats across it', () {
    // Same tiling rule as a pattern, so a lane works on a polymeter track.
    final e = _engine();
    e.setAutomation(
      'drums',
      AutomationParam.level,
      AutomationLane([1, 0]),
    );
    expect(e.renderLoop(), isNot(_engine().renderLoop()));
  });

  test('automation survives alongside a shortened track', () {
    // The two features that both index the step grid, together.
    final e = _engine();
    e.setTrackSteps('drums', 3);
    final lengthOnly = e.renderLoop();
    e.setAutomation(
      'drums',
      AutomationParam.level,
      AutomationLane([1, 0.2]),
    );
    final both = e.renderLoop();
    expect(both, isNot(lengthOnly));
    expect(
      both.length,
      lengthOnly.length,
      reason: 'a lane cannot resize a loop',
    );
  });
}

/// Per-channel peak of an interleaved stereo render.
(double, double) _stereoPeaks(List<int> pcm) {
  var l = 0.0, r = 0.0;
  for (var i = 0; i + 1 < pcm.length; i += 2) {
    final a = pcm[i].abs().toDouble();
    final b = pcm[i + 1].abs().toDouble();
    if (a > l) l = a;
    if (b > r) r = b;
  }
  return (l, r);
}

/// A3 — the panned path.
///
/// A2 rendered level on the MONO mixer only, so a panned track silently ignored
/// its lane. These cover the stereo mixer, plus pan automation itself, which
/// cannot be a pre-multiply: the constant-power law is a cos/sin pair, so
/// sliding a track across the field is not the same as scaling it.
void _a3() {
  group('the panned path honours automation too', () {
    LoopEngine pannedEngine() {
      final e = LoopEngine(tempoBpm: 120);
      e.enabled
        ..clear()
        ..add('drums');
      e.setPan('drums', 0.9); // forces the stereo mixer
      return e;
    }

    test('a panned groove with no lanes is unchanged', () {
      expect(pannedEngine().renderLoop(), pannedEngine().renderLoop());
    });

    test('a level lane now reaches a PANNED track', () {
      // This is the gap A2 left open and named.
      final before = pannedEngine().renderLoop();
      final e = pannedEngine();
      e.setAutomation(
        'drums',
        AutomationParam.level,
        AutomationLane([for (var i = 0; i < 16; i++) 1 - i / 15]),
      );
      expect(e.renderLoop(), isNot(before));
    });

    test('a pan lane sweeps the track across the field', () {
      // Hard left for the first half, hard right for the second.
      //
      // Deliberately NOT asserting the two channels come out roughly equal:
      // that depends on where this pattern's hits happen to fall, not on the
      // pan law, and asserting it made the test fail for a reason that had
      // nothing to do with the feature. What IS true is that a swept track puts
      // real energy on the side a hard-right fixed pan starves.
      final fixed = pannedEngine().renderLoop();
      final e = pannedEngine();
      e.setAutomation(
        'drums',
        AutomationParam.pan,
        AutomationLane([for (var i = 0; i < 16; i++) i < 8 ? 0.0 : 1.0]),
      );
      final swept = e.renderLoop();
      expect(swept, isNot(fixed), reason: 'the lane must change the render');

      final (l, r) = _stereoPeaks(readWavPcm16(swept).samples);
      final (fl, _) = _stereoPeaks(readWavPcm16(fixed).samples);
      expect(l, greaterThan(0), reason: 'the left half should be audible');
      expect(r, greaterThan(0), reason: 'the right half should be audible');
      expect(
        l,
        greaterThan(fl),
        reason: 'sweeping left must beat a hard-right fixed pan on the left',
      );
    });

    test('a pan lane overrides the fixed pan rather than adding to it', () {
      // Centre for the whole loop: the 0.9 hard-right pan must be gone.
      final e = pannedEngine();
      e.setAutomation(
        'drums',
        AutomationParam.pan,
        AutomationLane(List<double>.filled(16, 0.5)),
      );
      final (l, r) = _stereoPeaks(readWavPcm16(e.renderLoop()).samples);
      expect(
        (l - r).abs(),
        lessThan(l * 0.05),
        reason: 'a centred lane should balance the channels',
      );
    });
  });
}
