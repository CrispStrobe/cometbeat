// W-SEP (Spleeter 4-stem): a fast power-ratio-mask unit test + model-gated
// end-to-end separation checks against a kaldi-native-fbank + onnxruntime
// reference (the exact sherpa-onnx pipeline). The e2e tests skip when the
// Spleeter ONNX stems aren't cached (set COMET_SPLEETER_DIR).
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/separate_spleeter.dart';
import 'package:comet_beat/core/audio/transcription/separate_spleeter_model_store.dart';
import 'package:comet_beat/core/audio/transcription/stems.dart' show Separator;
import 'package:flutter_test/flutter_test.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

const int _sr = 44100;
const String _dir = 'test/transcription';

/// The exact deterministic MONO signal the reference oracle used.
Float64List synthMono(int n) {
  final x = Float64List(n);
  for (var i = 0; i < n; i++) {
    final t = i.toDouble();
    var v = 0.30 * math.sin(2 * math.pi * 220.0 * t / _sr) +
        0.20 * math.sin(2 * math.pi * 440.0 * t / _sr);
    v *= 0.8 + 0.2 * math.sin(2 * math.pi * 3.0 * t / _sr);
    x[i] = v;
  }
  return x;
}

Float32List readBin(String path) {
  final bd = ByteData.sublistView(File(path).readAsBytesSync());
  final count = bd.getInt32(0, Endian.little);
  final out = Float32List(count);
  for (var i = 0; i < count; i++) {
    out[i] = bd.getFloat32(4 + i * 4, Endian.little);
  }
  return out;
}

/// max|Δ| and correlation over the first [keep] interior samples (skip the
/// under-summed OLA edges).
(double, double) compare(Float64List got, Float32List ref, int keep) {
  final lo = 4096, hi = keep - 4096;
  var maxD = 0.0, dot = 0.0, ng = 0.0, nr = 0.0;
  for (var i = lo; i < hi; i++) {
    final d = (got[i] - ref[i]).abs();
    if (d > maxD) maxD = d;
    dot += got[i] * ref[i];
    ng += got[i] * got[i];
    nr += ref[i] * ref[i];
  }
  final cos = dot / (math.sqrt(ng) * math.sqrt(nr) + 1e-30);
  return (maxD, cos);
}

void main() {
  group('Spleeter power-ratio mask (pure)', () {
    test('masks are the Wiener ratio and sum to ~1', () {
      final a = Float32List.fromList([3, 0, 1, 5]);
      final b = Float32List.fromList([4, 0, 0, 5]);
      final masks = spleeterMasks([a, b]);
      // mask_a[0] = (9 + eps/2)/(9+16+eps) ≈ 0.36; mask_b[0] ≈ 0.64.
      expect(masks[0][0], closeTo(9 / 25, 1e-6));
      expect(masks[1][0], closeTo(16 / 25, 1e-6));
      // both silent → eps/2 each over eps → 0.5 / 0.5.
      expect(masks[0][1], closeTo(0.5, 1e-6));
      expect(masks[1][1], closeTo(0.5, 1e-6));
      // masks over all stems sum to ~1 at every bin.
      for (var i = 0; i < 4; i++) {
        expect(masks[0][i] + masks[1][i], closeTo(1.0, 1e-6));
      }
    });
  });

  group('Spleeter end-to-end (model-gated)', () {
    Future<Map<String, OnnxModel>?> tryLoad(SpleeterConfig cfg) async {
      try {
        return await SpleeterModelStore(config: cfg).load();
      } catch (_) {
        return null;
      }
    }

    test(
      '4-stem separation matches the sherpa/knf reference',
      () async {
        final models = await tryLoad(SpleeterConfig.fourStems);
        if (models == null) {
          // ignore: avoid_print
          print('SKIP: Spleeter 4-stem models unavailable.');
          return;
        }
        final res = spleeterSeparateNamed(
          synthMono(44100),
          models: [for (final n in spleeter4Stems) models[n]!],
          stemNames: spleeter4Stems,
        );
        for (final stem in spleeter4Stems) {
          final ref = readBin('$_dir/spleeter_e2e4_$stem.bin');
          final (maxD, cos) = compare(res[stem]!, ref, ref.length);
          expect(cos, greaterThan(0.9999), reason: '$stem cos=$cos');
          expect(maxD, lessThan(5e-3), reason: '$stem max|Δ|=$maxD');
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      '2-stem separation matches the sherpa/knf reference',
      () async {
        final models = await tryLoad(SpleeterConfig.twoStems);
        if (models == null) {
          // ignore: avoid_print
          print('SKIP: Spleeter 2-stem models unavailable.');
          return;
        }
        final res = spleeterSeparateNamed(
          synthMono(44100),
          models: [for (final n in spleeter2Stems) models[n]!],
          stemNames: spleeter2Stems,
        );
        for (final stem in spleeter2Stems) {
          final ref = readBin('$_dir/spleeter_e2e2_$stem.bin');
          final (maxD, cos) = compare(res[stem]!, ref, ref.length);
          expect(cos, greaterThan(0.9999), reason: '$stem cos=$cos');
          expect(maxD, lessThan(5e-3), reason: '$stem max|Δ|=$maxD');
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'concurrent separator (parallel isolates) == sync, matches reference',
      () async {
        final Separator sep;
        try {
          sep = await SpleeterModelStore().separator(concurrent: true);
        } catch (_) {
          // ignore: avoid_print
          print('SKIP: Spleeter 4-stem models unavailable.');
          return;
        }
        final mono = synthMono(44100);
        final stems = await sep(mono, 44100);
        final got = {
          'vocals': stems.vocals,
          'drums': stems.drums,
          'bass': stems.bass,
          'other': stems.other,
        };
        for (final stem in spleeter4Stems) {
          final ref = readBin('$_dir/spleeter_e2e4_$stem.bin');
          final (maxD, cos) = compare(got[stem]!, ref, ref.length);
          expect(cos, greaterThan(0.9999), reason: 'concurrent $stem cos=$cos');
          expect(maxD, lessThan(5e-3), reason: 'concurrent $stem max|Δ|=$maxD');
        }
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
