// FCPE end-to-end (model-gated): a 220 Hz tone → mel → model → local_argmax
// decode → ~220 Hz, and the pooled path is identical to sync. Skips if the
// model isn't available.
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/fcpe.dart';
import 'package:comet_beat/core/audio/transcription/fcpe_model_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/slow_tests.dart';

void main() {
  // Gated: see test/support/slow_tests.dart. Every test here needs a model.
  if (!kRunModelE2e) {
    test(
      describeSkip('MODEL_E2E', 'FCPE model inference'),
      () {},
    );
    return;
  }

  test(
    'a 220 Hz tone recovers ~220 Hz; pooled == sync',
    () async {
      FcpeBundle? b;
      try {
        b = await FcpeModelStore().load();
      } catch (_) {
        // ignore: avoid_print
        print('SKIP: FCPE model unavailable — skipping.');
        return;
      }
      const sr = 16000;
      final n = (sr * 1.2).round();
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

      final track = fcpeF0(y, model: b.model, assets: b.assets, sampleRate: sr);
      expect(track, isNotEmpty);
      final voiced = [
        for (final f in track)
          if (f.f0Hz > 50) f.f0Hz,
      ]..sort();
      expect(voiced, isNotEmpty);
      final median = voiced[voiced.length ~/ 2];
      // ignore: avoid_print
      print('FCPE median F0 (220 Hz tone): $median');
      expect(median, closeTo(220, 6));

      // The pooled path (shipped default) must be bitwise-identical to sync.
      await b.model.parallelize(workers: 2, poolConv: true);
      final pooled = await fcpeF0Async(
        y,
        model: b.model,
        assets: b.assets,
        sampleRate: sr,
      );
      b.model.dispose();
      expect(pooled.length, track.length);
      var maxDf = 0.0;
      for (var i = 0; i < track.length; i++) {
        maxDf = max(maxDf, (pooled[i].f0Hz - track[i].f0Hz).abs());
      }
      expect(maxDf, lessThan(1e-6), reason: 'pooled vs sync F0 drift');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
