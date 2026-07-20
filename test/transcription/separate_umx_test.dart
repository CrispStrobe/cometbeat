// W-SEP (Open-Unmix vocals): a model-gated mechanical check — the separator
// runs and produces a finite vocal stem of the right length. (Separation
// QUALITY is only meaningful on real music, so it isn't asserted here; umxhq
// mangles synthetic audio just as CREPE/BTC do.) Skips if the model is absent.
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/separate_umx.dart';
import 'package:comet_beat/core/audio/transcription/separate_umx_model_store.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart' show Stems;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'separateVocal produces a finite same-length stem',
    () async {
      UmxModelStore? store;
      try {
        store = UmxModelStore();
        if (!store.isPresent()) {
          await store.load(); // downloads (~36 MB) on first run
        }
      } catch (_) {
        // ignore: avoid_print
        print('SKIP: Open-Unmix model unavailable — skipping.');
        return;
      }
      final model = await store.load();

      const sr = 44100;
      // A 2 s "mix": a 330 Hz melody-ish tone over a low chord.
      const n = sr * 2;
      final mix = Float64List(n);
      for (var i = 0; i < n; i++) {
        final t = i / sr;
        mix[i] = 0.5 * sin(2 * pi * 330 * t) +
            0.3 * (sin(2 * pi * 98 * t) + sin(2 * pi * 147 * t));
      }

      final vocal = separateVocal(mix, model: model); // 44.1 kHz default
      expect(vocal.length, closeTo(n, 2048)); // ~same length
      var energy = 0.0, finite = true;
      for (final v in vocal) {
        if (!v.isFinite) finite = true == false;
        energy += v * v;
      }
      expect(finite, isTrue, reason: 'stem must be finite');
      expect(energy, greaterThan(0), reason: 'stem must not be silent');

      // The Separator seam returns a vocals-only Stems.
      final Stems stems = await umxSeparate(mix, model: model);
      expect(stems.vocals, isNotNull);
      expect(stems.bass, isNull);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
