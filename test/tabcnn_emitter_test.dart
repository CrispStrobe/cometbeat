// The audio→tab emission provider: windowing, peak-normalize, and the full
// emit→decode path driven by a synthetic CQT filterbank + a fake runner (no
// model, no network). A real-model smoke runs only when COMET_TABCNN_DIR points
// at a prebuilt tabcnn.onnx + tabcnn-cqt.bin.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/harmony_cqt.dart';
import 'package:comet_beat/features/games/composition/tab_emission_decoder.dart';
import 'package:comet_beat/features/games/composition/tabcnn_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

/// A tiny valid [CqtFilterBank]: [nBins] bins, each reading one FFT bin, no
/// normalization (mean 0 / std 1) — enough to exercise the emit pipeline.
CqtFilterBank _fakeCqt({int nBins = 8}) {
  const nFft = 16, hop = 8;
  final lengths = Float32List(nBins)..fillRange(0, nBins, 1);
  final lo = Int32List(nBins), hi = Int32List(nBins), off = Int32List(nBins);
  for (var k = 0; k < nBins; k++) {
    lo[k] = k + 1;
    hi[k] = k + 2;
    off[k] = k;
  }
  return CqtFilterBank(
    nBins: nBins,
    nFft: nFft,
    hop: hop,
    mean: 0,
    std: 1,
    lengths: lengths,
    lo: lo,
    hi: hi,
    off: off,
    re: Float32List(nBins)..fillRange(0, nBins, 1),
    im: Float32List(nBins),
  );
}

/// A fake TabCNN: every window says string 0 → fret 5 (class 6), the rest silent.
Float32List _fakeRunner(Float32List windows, int n) {
  final out = Float32List(n * kTabStrings * kTabClasses)
    ..fillRange(0, n * kTabStrings * kTabClasses, -8.0);
  for (var i = 0; i < n; i++) {
    final base = i * kTabStrings * kTabClasses;
    out[base + 0 * kTabClasses + 6] = -0.1; // string 0, class 6 = fret 5
    for (var s = 1; s < kTabStrings; s++) {
      out[base + s * kTabClasses + 0] = -0.1; // other strings silent
    }
  }
  return out;
}

void main() {
  test('peakNormalize scales to max |amp| = 1; silence unchanged', () {
    final n = peakNormalize(Float64List.fromList([0.5, -2.0, 1.0]));
    expect(n[1], closeTo(-1.0, 1e-12));
    expect(n[0], closeTo(0.25, 1e-12));
    expect(peakNormalize(Float64List(4)), Float64List(4)); // all-zero untouched
  });

  test('tabContextWindows centres a zero-padded 9-frame context, bin-major',
      () {
    // 3 frames × 2 bins; feat[t*2 + b] = t*10 + b.
    final feat = Float32List.fromList([0, 1, 10, 11, 20, 21]);
    final w = tabContextWindows(feat, 3, 2);
    const win = kTabCnnContext; // 9, centre index 4
    // Frame 0: valid source frames land at ctx 4,5,6 (src 0,1,2); ctx<4 padded.
    expect(w[0 * win + 4], 0); // bin 0, src frame 0
    expect(w[0 * win + 5], 10); // bin 0, src frame 1
    expect(w[0 * win + 6], 20); // bin 0, src frame 2
    expect(w[0 * win + 0], 0); // left edge padded
    expect(w[1 * win + 4], 1); // bin 1, src frame 0
    expect(w[1 * win + 6], 21); // bin 1, src frame 2
  });

  test('btcCqtFeature logMag:false is raw magnitude; true is its log', () {
    final cqt = _fakeCqt();
    final audio = Float64List(64);
    for (var i = 0; i < audio.length; i++) {
      audio[i] = math.sin(2 * math.pi * 3 * i / 16);
    }
    final (raw, n1) = btcCqtFeature(cqt, audio, logMag: false);
    final (log, n2) = btcCqtFeature(cqt, audio);
    expect(n1, n2);
    for (var k = 0; k < raw.length; k++) {
      expect(log[k], closeTo(math.log(raw[k] + 1e-6), 1e-5));
    }
  });

  test('emit → decode: fake runner drives the frets through the pipeline', () {
    // 0.5 s of audio at 22.05 kHz through the tiny filterbank (hop 8).
    final mono = Float64List(88);
    for (var i = 0; i < mono.length; i++) {
      mono[i] = 0.3 * math.sin(2 * math.pi * 4 * i / 16);
    }
    final frames = tabcnnEmitWithRunner(
      mono,
      cqt: _fakeCqt(),
      run: _fakeRunner,
      sampleRate: 22050,
    );
    expect(frames.nFrames, 1 + mono.length ~/ 8);
    expect(frames.hopSeconds, closeTo(8 / 22050, 1e-9));
    expect(frames.logProbs.length, frames.nFrames * 6 * 21);

    final tab = decodeTabEmissions(frames);
    expect(tab, hasLength(frames.nFrames));
    for (final f in tab) {
      expect(f.keys, [0]); // only string 0 sounding
      expect(f[0], 5); // fret 5
    }
  });

  test('gpfxNormalize maps raw magnitude to per-clip dB in [0,1]', () {
    // A spread of magnitudes; the max must map to 1, all values into [0,1].
    final raw = Float32List.fromList([0.001, 0.01, 0.1, 1.0, 0.5]);
    final n = gpfxNormalize(raw);
    expect(n.reduce(math.max), closeTo(1.0, 1e-6)); // loudest bin → 1
    expect(n.every((v) => v >= 0 && v <= 1.0 + 1e-6), isTrue);
    // Monotonic in magnitude (dB is monotonic, so the scaling preserves order).
    expect(n[0] < n[1] && n[1] < n[2] && n[2] < n[3], isTrue);
    expect(gpfxNormalize(Float32List(0)), isEmpty);
  });

  test('empty audio yields zero frames', () {
    final frames = tabcnnEmitWithRunner(
      Float64List(0),
      cqt: _fakeCqt(),
      run: _fakeRunner,
      sampleRate: 22050,
    );
    expect(frames.nFrames, 0);
    expect(decodeTabEmissions(frames), isEmpty);
  });

  test('the vanilla variant feeds raw magnitude (no gpfx dB re-scale)', () {
    final mono = Float64List(88);
    for (var i = 0; i < mono.length; i++) {
      mono[i] = 0.3 * math.sin(2 * math.pi * 4 * i / 16);
    }
    final frames = tabcnnEmitWithRunner(
      mono,
      cqt: _fakeCqt(),
      run: _fakeRunner,
      sampleRate: 22050,
      variant: TabCnnVariant.vanilla,
    );
    expect(frames.nFrames, greaterThan(0));
    // The fake runner still drives the fret through, whichever normalization.
    for (final f in decodeTabEmissions(frames)) {
      expect(f[0], 5);
    }
  });

  test('a non-native sample rate is resampled to the model rate', () {
    // 44.1 kHz input ≠ kTabCnnSampleRate (22.05 kHz) → the resample path runs.
    final mono = Float64List(176);
    for (var i = 0; i < mono.length; i++) {
      mono[i] = 0.3 * math.sin(2 * math.pi * 4 * i / 16);
    }
    final frames = tabcnnEmitWithRunner(
      mono,
      cqt: _fakeCqt(),
      run: _fakeRunner,
    );
    expect(frames.nFrames, greaterThan(0));
    expect(frames.logProbs.length, frames.nFrames * 6 * 21);
  });

  // Real-model smoke — only when the assets are present locally. Verifies the
  // onnx wiring runs end-to-end and emits well-formed [T,6,21] log-probs.
  testWidgets('TabCnnModelStore + real model emit (COMET_TABCNN_DIR gated)',
      (tester) async {
    final loaded = await TabCnnModelStore().load();
    if (loaded == null) return; // no assets / offline → skip
    expect(loaded.variant, TabCnnVariant.gpfx); // prefers the robust model
    final mono = Float64List(22050); // 1 s
    for (var i = 0; i < mono.length; i++) {
      mono[i] = 0.3 * math.sin(2 * math.pi * 196 * i / 22050); // ~G3
    }
    final frames = TabCnnEmitter(
      model: loaded.model,
      cqt: loaded.cqt,
      variant: loaded.variant,
    ).emit(mono, 22050);
    expect(frames, isNotNull);
    expect(frames!.nFrames, greaterThan(0));
    expect(frames.logProbs.length, frames.nFrames * 6 * 21);
    expect(frames.logProbs.every((v) => v.isFinite), isTrue);
    expect(frames.logProbs.every((v) => v <= 1e-3), isTrue); // log-probs ≤ 0
    expect(decodeTabEmissions(frames), hasLength(frames.nFrames));
  });
}
