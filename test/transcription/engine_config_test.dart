// The backend/model decision framework: resolve() applies the user's per-step
// preference, the platform, and which backends are actually available — never
// routing a Dart-only step to a neural engine, always falling back to pure-Dart.

import 'package:comet_beat/core/audio/transcription/engine_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cfg = TranscriptionEngineConfig();

  group('Dart-only steps never go neural', () {
    for (final step in kDartOnlySteps) {
      test('$step stays pure-Dart even with everything available', () {
        final r = step == TranscriptionStep.notation
            ? cfg.copyWith(backends: {step: Backend.crispasr}).resolve(
                step,
                isWeb: false,
                available: {Backend.crispasr, Backend.onnx},
              )
            : cfg.resolve(
                step,
                isWeb: false,
                available: {Backend.crispasr, Backend.onnx},
              );
        expect(r.backend, Backend.pureDart);
      });
    }
  });

  group('auto picks the best AVAILABLE backend', () {
    test('native + CrispASR present → CrispASR for F0', () {
      final r = cfg.resolve(
        TranscriptionStep.f0,
        isWeb: false,
        available: {Backend.crispasr, Backend.onnx},
      );
      expect(r.backend, Backend.crispasr);
    });

    test('native, only ONNX present → ONNX', () {
      final r = cfg.resolve(
        TranscriptionStep.f0,
        isWeb: false,
        available: {Backend.onnx},
      );
      expect(r.backend, Backend.onnx);
    });

    test('the 3-path order: ggml > native-ORT FFI > pure-Dart ONNX', () {
      // native-ORT FFI beats pure-Dart ONNX when both are present…
      expect(
        cfg.resolve(
          TranscriptionStep.f0,
          isWeb: false,
          available: {Backend.onnx, Backend.onnxFfi},
        ).backend,
        Backend.onnxFfi,
      );
      // …and CrispASR ggml beats both.
      expect(
        cfg.resolve(
          TranscriptionStep.f0,
          isWeb: false,
          available: {Backend.onnx, Backend.onnxFfi, Backend.crispasr},
        ).backend,
        Backend.crispasr,
      );
    });

    test('web never uses either FFI runtime', () {
      final r = cfg.resolve(
        TranscriptionStep.f0,
        isWeb: true,
        available: {Backend.onnxFfi, Backend.onnx, Backend.crispasr},
      );
      expect(r.backend, Backend.onnx); // both FFI runtimes excluded
    });

    test('native, nothing neural available → pure-Dart', () {
      final r = cfg.resolve(
        TranscriptionStep.f0,
        isWeb: false,
        available: const {},
      );
      expect(r.backend, Backend.pureDart);
    });

    test('web never uses CrispASR (no FFI) even if "available"', () {
      final r = cfg.resolve(
        TranscriptionStep.separation,
        isWeb: true,
        available: {Backend.crispasr},
      );
      expect(r.backend, Backend.pureDart); // crispasr unusable, no onnx → dart
    });

    test('web uses ONNX when present', () {
      final r = cfg.resolve(
        TranscriptionStep.polyphonic,
        isWeb: true,
        available: {Backend.onnx, Backend.crispasr},
      );
      expect(r.backend, Backend.onnx);
    });
  });

  group('explicit preference', () {
    test('is honoured when usable', () {
      final r = cfg.copyWith(
        backends: {TranscriptionStep.f0: Backend.onnx},
      ).resolve(
        TranscriptionStep.f0,
        isWeb: false,
        available: {Backend.onnx, Backend.crispasr},
      );
      expect(r.backend, Backend.onnx); // not the auto-preferred crispasr
    });

    test('falls back to pure-Dart when the chosen backend is unavailable', () {
      final r = cfg.copyWith(
        backends: {TranscriptionStep.f0: Backend.crispasr},
      ).resolve(
        TranscriptionStep.f0,
        isWeb: false,
        available: const {}, // crispasr not present
      );
      expect(r.backend, Backend.pureDart);
    });
  });

  group('quality → model size/quant', () {
    ResolvedEngine at(ModelQuality q) =>
        TranscriptionEngineConfig(quality: q).resolve(
          TranscriptionStep.f0,
          isWeb: false,
          available: {Backend.crispasr},
        );

    test('fast = tiny/q4k, balanced = tiny/q8, accurate = full/f16', () {
      expect(at(ModelQuality.fast).size, ModelSize.tiny);
      expect(at(ModelQuality.fast).quant, ModelQuant.q4k);
      expect(at(ModelQuality.balanced).size, ModelSize.tiny);
      expect(at(ModelQuality.balanced).quant, ModelQuant.q8);
      expect(at(ModelQuality.accurate).size, ModelSize.full);
      expect(at(ModelQuality.accurate).quant, ModelQuant.f16);
    });
  });

  test('JSON round-trips backends + quality', () {
    final c = const TranscriptionEngineConfig().copyWith(
      quality: ModelQuality.accurate,
      backends: {
        TranscriptionStep.f0: Backend.crispasr,
        TranscriptionStep.separation: Backend.onnx,
      },
    );
    final back = TranscriptionEngineConfig.fromJson(c.toJson());
    expect(back.quality, ModelQuality.accurate);
    expect(back.backendFor(TranscriptionStep.f0), Backend.crispasr);
    expect(back.backendFor(TranscriptionStep.separation), Backend.onnx);
    expect(back.backendFor(TranscriptionStep.chords), Backend.auto); // default
  });
}
