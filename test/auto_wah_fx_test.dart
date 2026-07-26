// FxType.autoWah — the LFO-swept resonant low-pass added to the shared FX rack
// (fx_chain.dart), built on the tracker's shared LFO + the biquad's click-free
// setFreq. Exercised through the public applyFxChain so it is tested exactly as
// every mode (audio editor, tab rig) will call it.
//
// Properties:
//  1. IDENTITY — mix 0 returns the dry signal; length is always preserved.
//  2. LOW-PASS — a tone far above the cutoff is heavily attenuated; a tone
//     below it passes.
//  3. STATIC == biquad — with depth 0 (no sweep) the cutoff is pinned at
//     baseFreq, so the output matches a plain resonant low-pass at baseFreq.
//  4. SWEEP — with depth 1 the cutoff moves, so the output DIFFERS from the
//     static (depth 0) render of the same input.

import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/crisp_dsp/biquad.dart';
import 'package:comet_beat/core/audio/fx/fx_chain.dart';
import 'package:comet_beat/core/audio/fx/fx_spec.dart';
import 'package:flutter_test/flutter_test.dart';

const _sr = 44100;

Float64List _tone(double hz, int n, {double amp = 0.5}) {
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * sin(2 * pi * hz * i / _sr);
  }
  return out;
}

double _rms(Float64List x, [int from = 0, int? to]) {
  final end = to ?? x.length;
  var s = 0.0;
  for (var i = from; i < end; i++) {
    s += x[i] * x[i];
  }
  return sqrt(s / (end - from));
}

List<FxSpec> _wah(Map<String, double> overrides) => [
      defaultFx(FxType.autoWah).copyWith(
        params: {...defaultFx(FxType.autoWah).params, ...overrides},
      ),
    ];

void main() {
  test('mix 0 is the dry signal; length preserved', () {
    final dry = _tone(440, 4096);
    final out = applyFxChain(dry, _wah({'mix': 0}), _sr);
    expect(out.length, dry.length);
    for (var i = 0; i < dry.length; i++) {
      expect(out[i], closeTo(dry[i], 1e-12));
    }
  });

  test('low-passes: a tone far above cutoff is attenuated, one below passes',
      () {
    // Static filter (no sweep) at 350 Hz so the test is deterministic.
    final fx = _wah({'octaves': 0, 'baseFreq': 350, 'q': 2});
    final high = _tone(9000, 8192);
    final low = _tone(120, 8192);
    final highOut = applyFxChain(high, fx, _sr);
    final lowOut = applyFxChain(low, fx, _sr);
    // Ignore the first 1024 samples (filter warm-up).
    final highRatio = _rms(highOut, 1024) / _rms(high, 1024);
    final lowRatio = _rms(lowOut, 1024) / _rms(low, 1024);
    expect(highRatio, lessThan(0.2), reason: '9 kHz should be cut');
    expect(lowRatio, greaterThan(0.5), reason: '120 Hz should pass');
  });

  test('depth 0 (no sweep) matches a plain resonant low-pass at baseFreq', () {
    final dry = _tone(600, 4096);
    final wah = applyFxChain(
      dry,
      _wah({'octaves': 0, 'baseFreq': 500, 'q': 3}),
      _sr,
    );
    final ref = biquadFx(dry, sampleRate: _sr.toDouble(), freq: 500, q: 3);
    for (var i = 0; i < dry.length; i++) {
      expect(wah[i], closeTo(ref[i], 1e-9));
    }
  });

  test('depth 1 sweeps: output differs from the static (depth 0) render', () {
    final dry = _tone(1500, 16384);
    final swept = applyFxChain(
      dry,
      _wah({'depth': 1, 'octaves': 3, 'rateHz': 2, 'baseFreq': 400}),
      _sr,
    );
    final static0 = applyFxChain(
      dry,
      _wah({'depth': 0, 'octaves': 3, 'rateHz': 2, 'baseFreq': 400}),
      _sr,
    );
    // They must diverge somewhere by a musically-audible amount.
    var maxDiff = 0.0;
    for (var i = 1024; i < dry.length; i++) {
      maxDiff = max(maxDiff, (swept[i] - static0[i]).abs());
    }
    expect(maxDiff, greaterThan(0.05));
  });

  test('waveform selector is honored (square differs from sine sweep)', () {
    final dry = _tone(1500, 8192);
    final sine = applyFxChain(dry, _wah({'waveform': 0, 'depth': 1}), _sr);
    final square = applyFxChain(dry, _wah({'waveform': 2, 'depth': 1}), _sr);
    var maxDiff = 0.0;
    for (var i = 1024; i < dry.length; i++) {
      maxDiff = max(maxDiff, (sine[i] - square[i]).abs());
    }
    expect(maxDiff, greaterThan(0.01));
  });
}
