// HuBERT/ContentVec content encoder: model-gated runtime-parity test against
// onnxruntime (the VC-stack linchpin). Skips if the ~290 MB ContentVec ONNX
// isn't cached (set COMET_HUBERT_DIR).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/hubert.dart';
import 'package:comet_beat/core/audio/transcription/hubert_model_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

import '../support/slow_tests.dart';

const String _dir = 'test/transcription';
const int _sr = 16000;

/// The exact deterministic input the reference oracle used.
Float64List synth(int n) {
  final x = Float64List(n);
  var peak = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i.toDouble();
    var v = 0.0;
    for (var h = 1; h < 6; h++) {
      v += (1.0 / h) * math.sin(2 * math.pi * 140.0 * h * t / _sr);
    }
    v *= 0.6 + 0.4 * math.sin(2 * math.pi * 2.0 * t / _sr);
    x[i] = v;
    if (v.abs() > peak) peak = v.abs();
  }
  for (var i = 0; i < n; i++) {
    x[i] = 0.5 * x[i] / peak;
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

void main() {
  // Gated: see test/support/slow_tests.dart. Every test here needs a model.
  if (!kRunModelE2e) {
    test(
      describeSkip('MODEL_E2E', 'HuBERT model inference'),
      () {},
    );
    return;
  }

  test(
    'ContentVec encoder matches onnxruntime (cosine ~1.0)',
    () async {
      final meta = jsonDecode(
        File('$_dir/hubert_meta.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final embShape = (meta['emb_shape'] as List).cast<int>();
      final refFrames = embShape[1], refDim = embShape[2];

      final OnnxModel model;
      try {
        model = await HubertModelStore().load();
      } catch (_) {
        // ignore: avoid_print
        print('SKIP: ContentVec model unavailable.');
        return;
      }

      final feats = hubertEncodeSync(synth(_sr), model: model);
      expect(feats.dim, refDim, reason: 'dim');
      expect(feats.frames, refFrames, reason: 'frames');

      final ref = readBin('$_dir/hubert_emb.bin');
      expect(feats.feats.length, ref.length, reason: 'feat length');

      var dot = 0.0, ng = 0.0, nr = 0.0, maxD = 0.0;
      for (var i = 0; i < ref.length; i++) {
        dot += feats.feats[i] * ref[i];
        ng += feats.feats[i] * feats.feats[i];
        nr += ref[i] * ref[i];
        final d = (feats.feats[i] - ref[i]).abs();
        if (d > maxD) maxD = d;
      }
      final cos = dot / (math.sqrt(ng) * math.sqrt(nr) + 1e-30);
      expect(cos, greaterThan(0.9999), reason: 'cos=$cos maxΔ=$maxD');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
