// Live: the real libcrispasr separators and beat tracker through the app's
// own wrappers. Skips itself when the lib or a model is not on this machine
// (CI, web, a fresh checkout) — run locally with the dev lib in
// ~/.cache/crispasr (tool/bundle_macos_tts.sh) or COMET_CRISPASR_LIB set.
@TestOn('vm')
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/practice/practice_mix.dart'
    show mixtureConsistent;
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_beats.dart';
import 'package:comet_beat/core/audio/transcription/crispasr_ffi_separate.dart';
import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// [seconds] of a 120 BPM click (a decaying 1 kHz burst on every beat) over a
/// sustained 220 Hz tone, at 44.1 kHz.
Float32List _clickAndTone(int seconds) {
  const sr = 44100;
  final out = Float32List(seconds * sr);
  for (var i = 0; i < out.length; i++) {
    final t = i / sr;
    final sinceBeat = t % 0.5;
    final click = sinceBeat < 0.03
        ? 0.6 * math.exp(-sinceBeat * 150) * math.sin(2 * math.pi * 1000 * t)
        : 0.0;
    out[i] = click + 0.2 * math.sin(2 * math.pi * 220 * t);
  }
  return out;
}

void main() {
  // How closely each model's raw stems add back up to the mix, measured on
  // this click+tone signal, with headroom: htdemucs 15.2 dB, Mini-BS-RoFormer
  // 40.2 dB on the CPU. (On Metal it was ~4 dB — CrispASR #568, which is why
  // that model runs on the CPU.) htdemucs's 15 dB is still audible as a duller
  // song with every stem on, which is why the player runs mixtureConsistent.
  for (final (model, minDb) in [
    (CrispasrSeparatorModel.htdemucs, 10.0),
    (CrispasrSeparatorModel.miniBsRoformer, 30.0),
  ]) {
    test(
      '${model.registryBackend}: four stereo stems, input length, 44.1 kHz',
      () async {
        if (!await crispasrSeparatorAvailable(model)) {
          markTestSkipped('${model.registryBackend} not available here');
          return;
        }
        final mix = _clickAndTone(10);
        final stems =
            await separateStereoCrispasr(mix, mix, 44100, model: model);
        expect(stems, isNotNull);
        expect(
          stems!.map((s) => s.name).toSet(),
          {'vocals', 'drums', 'bass', 'other'},
        );
        for (final s in stems) {
          expect(s.sampleRate, 44100);
          expect(s.frames, mix.length);
        }
        double reconstructionDb(List<SeparatedStem> st) {
          var err = 0.0, sig = 0.0;
          for (var i = 0; i < mix.length; i++) {
            var sum = 0.0;
            for (final s in st) {
              sum += s.left[i];
            }
            err += (sum - mix[i]) * (sum - mix[i]);
            sig += mix[i] * mix[i];
          }
          return 10 * math.log(sig / math.max(err, 1e-20)) / math.ln10;
        }

        expect(reconstructionDb(stems), greaterThan(minDb));
        // After the player's projection, "everything on" IS the mix.
        expect(
          reconstructionDb(mixtureConsistent(stems, mix, mix)),
          greaterThan(60),
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }

  test(
    'beat-this finds a 120 BPM click',
    () async {
      if (!await crispasrBeatsAvailable()) {
        markTestSkipped('beat-this not available here');
        return;
      }
      final mix = _clickAndTone(12);
      final mono = Float64List(mix.length);
      for (var i = 0; i < mix.length; i++) {
        mono[i] = mix[i];
      }
      final grid = await crispasrBeatGrid(mono, 44100);
      expect(grid, isNotNull);
      expect(grid!.bpm, closeTo(120, 3));
      // Beats half a second apart, give or take a frame of the model.
      final gaps = [
        for (var i = 1; i < grid.beatMs.length; i++)
          grid.beatMs[i] - grid.beatMs[i - 1],
      ]..sort();
      expect(gaps[gaps.length ~/ 2], closeTo(500, 25));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
