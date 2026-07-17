// Tests for the AEC auto-tuner tooling (bin/aec_tune/). Two concerns:
//   1. the optimizer is CORRECT — it minimizes known functions to near-optimum
//      (so we can trust it on the opaque AEC objective);
//   2. the corpus + objective are well-formed and the objective actually
//      discriminates a good config from a broken one (a sanity gate on the
//      thing the optimizer maximizes).

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/aec_offline.dart';
import 'package:comet_beat/core/audio/synth.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bin/aec_tune/cmaes.dart';
import '../bin/aec_tune/corpus.dart';
import '../bin/aec_tune/objective.dart';

double _logistic(double z) => 1 / (1 + exp(-z));

void main() {
  group('CMA-ES optimizer (ground-truth correctness)', () {
    test('minimizes the sphere function to near-zero', () {
      // f(x) = sum x_i^2, optimum 0 at the origin. Start well off it.
      double sphere(List<double> x) =>
          x.map((v) => v * v).reduce((a, b) => a + b);
      final r = cmaesMinimize(
        sphere,
        initialMean: [3.0, -2.5, 4.0, 1.5],
        sigma0: 1.0,
        maxEvals: 3000,
        rng: Random(1),
      );
      expect(
        r.bestValue,
        lessThan(1e-6),
        reason: 'sphere min ${r.bestValue} after ${r.evaluations} evals',
      );
      for (final v in r.best) {
        expect(v.abs(), lessThan(1e-3));
      }
    });

    test('minimizes the ill-conditioned ellipsoid (per-coord scale adaptation)',
        () {
      // f(x) = sum (1000^(i/(n-1)) x_i)^2 — separable but with axis scales
      // spanning 10^6. This is the RIGHT stress test for the separable variant:
      // it must learn a different variance per coordinate. (Rosenbrock, whose
      // valley is diagonally CORRELATED, is deliberately out of scope for a
      // diagonal covariance — that's the documented cost of dropping the
      // off-diagonal terms, not a bug.)
      const n = 4;
      double ellipsoid(List<double> x) {
        var s = 0.0;
        for (var i = 0; i < n; i++) {
          final scale = pow(1000.0, i / (n - 1));
          s += pow(scale * x[i], 2).toDouble();
        }
        return s;
      }

      final r = cmaesMinimize(
        ellipsoid,
        initialMean: List<double>.filled(n, 1.0),
        sigma0: 1.0,
        maxEvals: 5000,
        rng: Random(2),
      );
      expect(
        r.bestValue,
        lessThan(1e-4),
        reason: 'ellipsoid min ${r.bestValue} after ${r.evaluations} evals',
      );
    });
  });

  group('loudspeaker nonlinearity model', () {
    test('linear mode is an exact passthrough', () {
      final x = Float64List.fromList([0.1, -0.4, 0.9, -0.2, 0.0]);
      final y = applyLoudspeaker(x, Loudspeaker.linear, 4);
      for (var i = 0; i < x.length; i++) {
        expect(y[i], x[i]);
      }
    });

    test(
        'distorting modes hold the RMS but change the waveform (add harmonics)',
        () {
      // A pure tone: after a memoryless nonlinearity its RMS is preserved (level
      // held) but its shape differs (energy moved into harmonics) — exactly what
      // a linear echo filter cannot cancel.
      final x = Float64List(4096);
      for (var i = 0; i < x.length; i++) {
        x[i] = 0.6 * sin(2 * pi * 5 * i / x.length);
      }
      double rms(Float64List v) {
        var s = 0.0;
        for (final e in v) {
          s += e * e;
        }
        return sqrt(s / v.length);
      }

      for (final mode in [Loudspeaker.hardClip, Loudspeaker.sigmoid]) {
        final y = applyLoudspeaker(x, mode, 4);
        expect(
          rms(y),
          closeTo(rms(x), rms(x) * 0.02),
          reason: '$mode should hold RMS',
        );
        var maxDiff = 0.0;
        for (var i = 0; i < x.length; i++) {
          maxDiff = max(maxDiff, (y[i] - x[i]).abs());
        }
        expect(
          maxDiff,
          greaterThan(0.05 * rms(x)),
          reason: '$mode should change the waveform',
        );
      }
    });

    test('nonlinear echo costs the linear filter, and RES recovers it', () {
      // The headline: a hard-clipped (nonlinear) echo the reference doesn't
      // contain hurts the adaptive filter's fidelity, and a residual-suppression
      // stage recovers most of it. Small corpus for speed.
      final linear = buildCorpus(rooms: 3, nearMidis: const [57]);
      final nonlinear = buildCorpus(
        rooms: 3,
        nearMidis: const [57],
        loudspeaker: Loudspeaker.hardClip,
        drive: 4,
      );
      const adaptive = AecTuning(adaptiveRate: true);
      final lin = scoreTuning(adaptive, linear);
      final nl = scoreTuning(adaptive, nonlinear);
      final nlRes = scoreTuning(adaptive, nonlinear, residualSuppress: true);
      expect(
        nl.meanSiSdr,
        lessThan(lin.meanSiSdr),
        reason: 'distortion must cost SI-SDR: lin $lin vs nl $nl',
      );
      expect(
        nlRes.meanSiSdr,
        greaterThan(nl.meanSiSdr),
        reason: 'RES must recover some: nl $nl vs +RES $nlRes',
      );
    });
  });

  group('AEC corpus + objective', () {
    test('the corpus has ground truth and a real double-talk region', () {
      final corpus = buildCorpus(rooms: 2, nearMidis: const [69]);
      expect(corpus, isNotEmpty);
      for (final s in corpus) {
        expect(s.mic.length, s.ref.length);
        expect(s.trueNear.length, s.mic.length);
        expect(s.doubleTalkFrom, greaterThan(0));
        // Near-end is silent before double-talk, present after.
        expect(s.trueNear[s.doubleTalkFrom ~/ 2], 0.0);
        var energyAfter = 0.0;
        for (var i = s.doubleTalkFrom; i < s.trueNear.length; i++) {
          energyAfter += s.trueNear[i] * s.trueNear[i];
        }
        expect(energyAfter, greaterThan(0));
      }
    });

    test('the objective ranks a working config above a broken one', () {
      final corpus = buildCorpus(rooms: 2, nearMidis: const [69, 57]);
      // Working: the adaptive rate. Broken: mu pinned to ~0 so the filter never
      // adapts and the echo is never removed.
      final good = scoreTuning(const AecTuning(adaptiveRate: true), corpus);
      final broken = scoreTuning(const AecTuning(mu: 1e-6), corpus);
      expect(
        good.score,
        greaterThan(broken.score),
        reason: 'good $good vs broken $broken',
      );
      // And the working config actually recovers most notes.
      expect(good.noteSurvival, greaterThan(0.5));
    });

    test('the full tune loop improves on the untuned adaptive baseline', () {
      // End-to-end: CMA-ES over the rate's own constants must not do WORSE than
      // where it started (the untuned adaptive rate) — the search begins from
      // those defaults and tracks the best point, so improvement is the floor.
      final corpus = buildCorpus(rooms: 2, nearMidis: const [69]);
      final baseline = scoreTuning(const AecTuning(adaptiveRate: true), corpus);
      // A small budget: enough to move, fast enough for CI.
      final r = cmaesMinimize(
        (z) {
          final gamma = 0.01 + 0.49 * _logistic(z[0]);
          final beta0 = 0.005 + 0.295 * _logistic(z[1]);
          final muMax = 0.1 + 0.9 * _logistic(z[2]);
          return -scoreTuning(
            AecTuning(
              adaptiveRate: true,
              rateGamma: gamma,
              rateBeta0: beta0,
              rateMuMax: muMax,
            ),
            corpus,
          ).score;
        },
        initialMean: [0, 0, 0],
        sigma0: 1.0,
        maxEvals: 60,
        rng: Random(3),
      );
      expect(
        -r.bestValue,
        greaterThanOrEqualTo(baseline.score - 1e-9),
        reason: 'tuned ${-r.bestValue} vs baseline ${baseline.score}',
      );
    });
  });

  group('real-acoustics corpus loader (buildCorpusFromAssets)', () {
    // Exercises the tier-2 loader WITHOUT the real downloads: write a tiny
    // synthetic RIR WAV and a sustained-note WAV to a temp dir, then check the
    // loader reads them, detects the note, and builds a scored-able scenario.
    // The real MIT-IR × Iowa-cello corpus is manually verified (needs the
    // multi-MB assets, which don't belong in CI).
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('aec_assets'));
    tearDown(() => tmp.deleteSync(recursive: true));

    void writeWav(String path, Float64List mono) {
      final pcm = Int16List(mono.length);
      for (var i = 0; i < mono.length; i++) {
        pcm[i] = (mono[i].clamp(-1.0, 1.0) * 32767).round();
      }
      File(path).writeAsBytesSync(wavBytes(pcm));
    }

    test('loads RIR + cello WAVs, detects the note, builds scenarios', () {
      final rirDir = Directory('${tmp.path}/rir')..createSync();
      final celloDir = Directory('${tmp.path}/cello')..createSync();

      // A short synthetic RIR (a couple of reflections).
      final ir = Float64List(200);
      ir[10] = 0.8;
      ir[60] = -0.3;
      ir[130] = 0.15;
      writeWav('${rirDir.path}/room.wav', ir);

      // A sustained A3 (220 Hz) "cello" note, long enough for several windows.
      const midiA3 = 57;
      final f = 440.0 * pow(2.0, (midiA3 - 69) / 12.0);
      final cello = Float64List(44100 * 8);
      for (var i = 0; i < cello.length; i++) {
        final t = i / 44100;
        cello[i] = 0.5 * sin(2 * pi * f * t);
      }
      writeWav('${celloDir.path}/note.wav', cello);

      final corpus = buildCorpusFromAssets(
        rirDir: rirDir.path,
        celloDir: celloDir.path,
        seconds: 2.0,
        windowsPerCello: 2,
      );
      expect(corpus, isNotEmpty);
      // The detector may read a harmonic, so assert the note is a stable A
      // (octave-robust) rather than exactly midi 57.
      for (final s in corpus) {
        expect(
          s.nearMidi % 12,
          midiA3 % 12,
          reason: 'detected ${s.nearMidi}, expected an A',
        );
        expect(s.mic.length, s.trueNear.length);
        expect(s.doubleTalkFrom, s.mic.length ~/ 2);
      }
      // And the objective runs on it end to end.
      final score = scoreTuning(const AecTuning(adaptiveRate: true), corpus);
      expect(score.noteSurvival, greaterThanOrEqualTo(0.0));
    });

    test('throws a clear error when a directory has no WAVs', () {
      final empty = Directory('${tmp.path}/empty')..createSync();
      expect(
        () => buildCorpusFromAssets(rirDir: empty.path, celloDir: empty.path),
        throwsStateError,
      );
    });
  });
}
