// test/transcription/crepe_test.dart
//
// W-CREPE tests. Two tiers:
//  • Deterministic (no model): the weighted-argmax decoder matches a torchcrepe
//    reference activation → f0 fixture exactly, and a hand-built activation
//    decodes to the expected pitch. These pin the port without a network/model.
//  • Model-gated (skip-if-absent): the real CREPE-tiny ONNX end-to-end — a 440 Hz
//    tone recovers ~440 Hz, and a C-major scale through the F0Estimator seam
//    transcribes to the right notes with ZERO octave errors (the whole reason
//    CREPE exists here — pYIN octave-doubles on real singing).
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/contracts.dart';
import 'package:comet_beat/core/audio/transcription/crepe.dart';
import 'package:comet_beat/core/audio/transcription/crepe_model_store.dart';
import 'package:comet_beat/core/audio/transcription/route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

import '../support/slow_tests.dart';
import 'note_metrics.dart';

const _sr = 44100;

Float64List _tone(double hz, double seconds, {int sr = _sr, double amp = 0.5}) {
  final n = (seconds * sr).round();
  final out = Float64List(n);
  for (var i = 0; i < n; i++) {
    out[i] = amp * sin(2 * pi * hz * i / sr);
  }
  return out;
}

double _hz(int midi) => 440 * pow(2, (midi - 69) / 12).toDouble();

Float64List _scale(List<int> midis) {
  final parts = <Float64List>[];
  for (final m in midis) {
    parts.add(_tone(_hz(m), 0.4));
    parts.add(Float64List((0.08 * _sr).round())); // 80 ms rest
  }
  final total = parts.fold<int>(0, (s, p) => s + p.length);
  final out = Float64List(total);
  var off = 0;
  for (final p in parts) {
    out.setAll(off, p);
    off += p.length;
  }
  return out;
}

/// Loads the CREPE model if it can be provisioned (cached or downloadable);
/// returns null offline so model-gated tests skip instead of failing.
Future<OnnxModel?> _tryModel() async {
  // Prefer a model already in the shared onnx_runtime_dart cache; fall back to
  // the store's own download.
  final home = Platform.environment['HOME'] ?? '';
  for (final dir in [
    if (home.isNotEmpty) '$home/.cache/onnx_runtime_dart_models',
    null,
  ]) {
    try {
      final store = CrepeModelStore(cacheDirOverride: dir);
      return await store.load();
    } catch (_) {
      // try next source
    }
  }
  return null;
}

void main() {
  group('CREPE decoder (deterministic, no model)', () {
    test('weighted-argmax matches the torchcrepe reference activation → f0',
        () {
      final ref = jsonDecode(
        File('test/transcription/crepe_decode_ref.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final n = ref['nframes'] as int;
      final bins = ref['bins'] as int;
      expect(bins, 360);
      final rows = (ref['activation'] as List).cast<List<dynamic>>();
      final expF0 = (ref['f0Hz'] as List).cast<num>();

      final flat = Float32List(n * bins);
      for (var f = 0; f < n; f++) {
        for (var b = 0; b < bins; b++) {
          flat[f * bins + b] = (rows[f][b] as num).toDouble();
        }
      }
      final decoded = decodeCrepeActivation(flat, n);
      expect(decoded.length, n);
      for (var f = 0; f < n; f++) {
        // Reproduces torchcrepe's weighted_argmax to float precision. The
        // reference has torchcrepe's random anti-quantization dither DISABLED —
        // our decode omits it deliberately (deterministic output is better for
        // note segmentation), so the two agree to <0.01 Hz (7-dp fixture).
        expect(
          decoded[f].$1,
          closeTo(expF0[f].toDouble(), 0.01),
          reason: 'frame $f: got ${decoded[f].$1}, want ${expF0[f]}',
        );
      }
    });

    test('a single-bin peak decodes to that bin\'s frequency', () {
      // Bin 228 ≈ 440 Hz (cents = 20*228 + 1997.379 = 6557.4 → 441.6 Hz).
      const bins = 360;
      final act = Float32List(bins); // sigmoid(0)=0.5 elsewhere
      act[228] = 8.0; // sharp peak
      final decoded = decodeCrepeActivation(act, 1);
      expect(decoded.single.$1, closeTo(441.6, 2.0));
      expect(decoded.single.$2, closeTo(8.0.clamp(0, 1), 1e-6)); // voicing=peak
    });

    test('f0 stays inside the fmin/fmax gate', () {
      const bins = 360;
      // Peaks below fmin (bin 0) and above fmax (bin 359) must be ignored.
      final low = Float32List(bins)..[0] = 9.0;
      final high = Float32List(bins)..[359] = 9.0;
      final dl = decodeCrepeActivation(low, 1).single.$1; // default 50–2006 Hz
      final dh = decodeCrepeActivation(high, 1).single.$1;
      expect(dl, greaterThanOrEqualTo(50));
      expect(dh, lessThanOrEqualTo(2006));
    });
  });

  group('CREPE end-to-end (model-gated)', () {
    // Gated: see test/support/slow_tests.dart.
    if (!kRunModelE2e) {
      test(
        describeSkip('MODEL_E2E', 'CREPE model inference'),
        () {},
      );
      return;
    }
    late final OnnxModel? model;
    setUpAll(() async {
      model = await _tryModel();
      if (model == null) {
        // ignore: avoid_print
        print('SKIP: CREPE model unavailable (offline, no cache) — '
            'skipping model-gated tests.');
      }
    });

    test('a 440 Hz tone recovers ~440 Hz with high voicing', () {
      if (model == null) return;
      final track = crepeF0(_tone(440, 0.5), model: model!); // 44.1 kHz default
      expect(track, isNotEmpty);
      final voiced = [
        for (final f in track)
          if (f.voicedProb > 0.4) f.f0Hz,
      ]..sort();
      expect(voiced, isNotEmpty);
      final median = voiced[voiced.length ~/ 2];
      expect(median, closeTo(440, 6), reason: 'median f0 $median');
    });

    test('silence produces low voicing throughout', () {
      if (model == null) return;
      final track = crepeF0(Float64List(_sr ~/ 2), model: model!);
      expect(track, isNotEmpty);
      final voicedFrac =
          track.where((f) => f.voicedProb > 0.5).length / track.length;
      expect(voicedFrac, lessThan(0.2), reason: 'voiced frac $voicedFrac');
    });

    test('a C-major scale transcribes to the right notes, ZERO octave errors',
        () async {
      if (model == null) return;
      const song = [60, 62, 64, 65, 67, 69, 71, 72]; // C4..C5
      final audio = _scale(song);
      estimator(Float64List m, int sr) =>
          crepeF0(m, model: model!, sampleRate: sr);
      final detected = await transcribeMonophonic(audio, f0: estimator);

      final expected = notes([
        for (var i = 0; i < song.length; i++)
          (song[i], i * 480.0, i * 480.0 + 400),
      ]);

      // Exact-pitch note F (pitchTol:0) — an octave-doubled note would miss the
      // exact MIDI and tank this.
      expect(
        notePrf(expected, detected, onsetTolMs: 200).f,
        greaterThanOrEqualTo(0.9),
        reason: 'detected: ${detected.map((n) => n.midi).toList()}',
      );

      // Explicit octave-error guard: no detected note sits exactly ±12 from the
      // nearest expected onset while missing the exact pitch.
      final octaveErrors = <int>[];
      for (final d in detected) {
        NoteEvent? nearest;
        var best = double.infinity;
        for (final e in expected) {
          final dt = (e.onMs - d.onMs).abs();
          if (dt < best && dt <= 200) {
            best = dt;
            nearest = e;
          }
        }
        if (nearest != null && (d.midi - nearest.midi).abs() == 12) {
          octaveErrors.add(d.midi);
        }
      }
      expect(octaveErrors, isEmpty, reason: 'octave errors: $octaveErrors');
    });
  });
}
