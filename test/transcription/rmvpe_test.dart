// W-RMVPE: deterministic decode tests + a model-gated end-to-end F0 check
// (skips if the ~361 MB model isn't cached).
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/rmvpe.dart';
import 'package:comet_beat/core/audio/transcription/rmvpe_model_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/slow_tests.dart';

void main() {
  group('RMVPE decode (deterministic, no model)', () {
    test('a single-bin salience peak decodes to that bin frequency', () {
      // Bin 228 → cents 20·228+1997.379 = 6557.4 → 441.6 Hz.
      final sal = Float32List(360);
      sal[228] = 0.9;
      final (hz, voiced) = decodeRmvpeSalience(sal, 1).single;
      expect(hz, closeTo(441.6, 3.0));
      expect(voiced, closeTo(0.9, 1e-6));
    });

    test('a below-threshold frame is unvoiced (F0 0)', () {
      final sal = Float32List(360);
      for (var b = 0; b < 360; b++) {
        sal[b] = 0.01; // < 0.03 threshold
      }
      final (hz, _) = decodeRmvpeSalience(sal, 1).single;
      expect(hz, 0.0);
    });
  });

  group('RMVPE end-to-end (model-gated)', () {
    // Gated: see test/support/slow_tests.dart.
    if (!kRunModelE2e) {
      test(
        describeSkip('MODEL_E2E', '~361 MB model, minutes of inference'),
        () {},
      );
      return;
    }
    test(
      'a 220 Hz tone recovers ~220 Hz',
      () async {
        RmvpeBundle? bundle;
        try {
          bundle = await RmvpeModelStore().load(); // cached or downloads
        } catch (_) {
          // ignore: avoid_print
          print('SKIP: RMVPE model unavailable — skipping.');
          return;
        }
        const sr = 16000;
        // 5-harmonic 220 Hz, 1 s.
        const n = sr;
        final y = Float64List(n);
        var peak = 0.0;
        for (var i = 0; i < n; i++) {
          var s = 0.0;
          for (var k = 1; k <= 5; k++) {
            s += (1.0 / k) * sin(2 * pi * k * 220 * i / sr);
          }
          y[i] = s;
          if (s.abs() > peak) peak = s.abs();
        }
        for (var i = 0; i < n; i++) {
          y[i] /= peak;
        }

        final track =
            rmvpeF0(y, model: bundle.model, mel: bundle.mel, sampleRate: sr);
        expect(track, isNotEmpty);
        final voiced = [
          for (final f in track)
            if (f.f0Hz > 0) f.f0Hz,
        ]..sort();
        expect(voiced, isNotEmpty);
        final median = voiced[voiced.length ~/ 2];
        // ignore: avoid_print
        print('RMVPE median F0 (220 Hz tone): $median');
        expect(median, closeTo(220, 6));

        // The isolate-pool path (the shipped default) must be identical to sync.
        await bundle.model.parallelize(workers: 2, poolConv: true);
        final pooled = await rmvpeF0Async(
          y,
          model: bundle.model,
          mel: bundle.mel,
          sampleRate: sr,
        );
        bundle.model.dispose();
        expect(pooled.length, track.length);
        var maxDf = 0.0;
        for (var i = 0; i < track.length; i++) {
          maxDf = max(maxDf, (pooled[i].f0Hz - track[i].f0Hz).abs());
        }
        expect(maxDf, lessThan(1e-6), reason: 'pooled vs sync F0 drift');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
