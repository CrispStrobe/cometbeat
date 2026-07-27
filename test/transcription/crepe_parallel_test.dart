// test/transcription/crepe_parallel_test.dart
//
// The isolate-pool path must produce the SAME F0 as the single-threaded path —
// parallelism is a speed knob, never a correctness one. Also covers the env
// gating that selects between the two.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:comet_beat/core/audio/transcription/crepe.dart';
import 'package:comet_beat/core/audio/transcription/crepe_model_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

import '../support/slow_tests.dart';

Future<OnnxModel?> _tryModel() async {
  final home = Platform.environment['HOME'] ?? '';
  for (final dir in [
    if (home.isNotEmpty) '$home/.cache/onnx_runtime_dart_models',
    null,
  ]) {
    try {
      return await CrepeModelStore(cacheDirOverride: dir).load();
    } catch (_) {
      // try next
    }
  }
  return null;
}

void main() {
  group('CrepeRunConfig.fromEnv (deterministic, no model)', () {
    test('defaults to the isolate pool (auto worker count)', () {
      final c = CrepeRunConfig.fromEnv(const {});
      expect(c.workers, autoPoolWorkers()); // pool on by default
      expect(c.poolConv, isTrue);
      expect(c.batchFrames, 512);
    });

    test('COMET_CREPE_WORKERS=0 disables the pool', () {
      final c = CrepeRunConfig.fromEnv(const {'COMET_CREPE_WORKERS': '0'});
      expect(c.workers, 0);
      expect(c.parallel, isFalse);
    });

    test('parses workers / poolConv / batch and flips to parallel', () {
      final c = CrepeRunConfig.fromEnv(const {
        'COMET_CREPE_WORKERS': '4',
        'COMET_CREPE_POOLCONV': 'false',
        'COMET_CREPE_BATCH': '256',
      });
      expect(c.workers, 4);
      expect(c.parallel, isTrue);
      expect(c.poolConv, isFalse);
      expect(c.batchFrames, 256);
    });

    test('bad values fall back to defaults', () {
      final c = CrepeRunConfig.fromEnv(const {'COMET_CREPE_WORKERS': 'nope'});
      expect(c.workers, autoPoolWorkers());
    });
  });

  group('parallel path parity (model-gated)', () {
    // Gated: see test/support/slow_tests.dart.
    if (!kRunModelE2e) {
      test(
        describeSkip('MODEL_E2E', 'CREPE parallel-path parity'),
        () {},
      );
      return;
    }
    test(
      'crepeF0Async on the pool == crepeF0 sync, frame-for-frame',
      () async {
        final model = await _tryModel();
        if (model == null) {
          // ignore: avoid_print
          print('SKIP: CREPE model unavailable — skipping parallel parity.');
          return;
        }
        // Short signal (a few hundred ms) so it stays quick even under load.
        const sr = 16000;
        final audio = Float64List((sr * 0.4).round());
        for (var i = 0; i < audio.length; i++) {
          audio[i] = 0.5 * sin(2 * pi * 330 * i / sr);
        }

        final sync = crepeF0(audio, model: model, sampleRate: sr);

        // Set up a 2-isolate pool (poolConv so CREPE's Conv actually parallelises)
        // and run the async path over the SAME model.
        await model.parallelize(workers: 2, poolConv: true);
        final async = await crepeF0Async(audio, model: model, sampleRate: sr);
        model.dispose();

        expect(async.length, sync.length);
        var maxDf = 0.0, maxDv = 0.0;
        for (var i = 0; i < sync.length; i++) {
          maxDf = max(maxDf, (async[i].f0Hz - sync[i].f0Hz).abs());
          maxDv = max(maxDv, (async[i].voicedProb - sync[i].voicedProb).abs());
        }
        // The pool is documented bitwise-identical; allow a hair for float order.
        expect(
          maxDf,
          lessThan(1e-6),
          reason: 'f0 drift pooled-vs-sync: $maxDf',
        );
        expect(maxDv, lessThan(1e-6), reason: 'voicing drift: $maxDv');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
