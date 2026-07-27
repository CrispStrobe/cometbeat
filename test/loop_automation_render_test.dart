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
