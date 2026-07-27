import 'package:comet_beat/core/audio/tts/tts_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveTtsEngines', () {
    test('native auto: crispasr-FFI first, platform floor', () {
      final r = resolveTtsEngines(
        isWeb: false,
        available: {TtsEngine.crispasrFfi, TtsEngine.onnxFfi},
      );
      expect(r.first, TtsEngine.crispasrFfi);
      expect(r, containsAllInOrder([TtsEngine.crispasrFfi, TtsEngine.onnxFfi]));
      expect(r.last, TtsEngine.platform);
    });

    test('native falls down the chain as engines drop out', () {
      expect(
        resolveTtsEngines(isWeb: false, available: {TtsEngine.pureDartOnnx}),
        [TtsEngine.pureDartOnnx, TtsEngine.platform],
      );
      expect(
        resolveTtsEngines(isWeb: false, available: {}),
        [TtsEngine.platform],
      );
    });

    test('web excludes FFI engines entirely', () {
      final r = resolveTtsEngines(
        isWeb: true,
        available: {TtsEngine.crispasrFfi, TtsEngine.onnxFfi},
      );
      expect(r, [TtsEngine.platform]); // both FFI → dropped on web
    });

    test('web excludes pure-Dart ONNX (too slow live) but allows wasm', () {
      expect(
        resolveTtsEngines(isWeb: true, available: {TtsEngine.pureDartOnnx}),
        [TtsEngine.platform], // pure-dart-onnx not interactive-viable on web
      );
      expect(
        resolveTtsEngines(isWeb: true, available: {TtsEngine.crispasrWasm}),
        [TtsEngine.crispasrWasm, TtsEngine.platform],
      );
    });

    test('an explicit usable preference takes the top slot', () {
      final r = resolveTtsEngines(
        isWeb: false,
        available: {TtsEngine.crispasrFfi, TtsEngine.onnxFfi},
        preferred: TtsEngine.onnxFfi,
      );
      expect(r.first, TtsEngine.onnxFfi);
      expect(r, contains(TtsEngine.crispasrFfi));
    });

    test('an unusable preference is ignored, auto chain applies', () {
      // Prefer crispasr-FFI on web → impossible (FFI) → falls to the web chain.
      final r = resolveTtsEngines(
        isWeb: true,
        available: {TtsEngine.crispasrWasm},
        preferred: TtsEngine.crispasrFfi,
      );
      expect(r, [TtsEngine.crispasrWasm, TtsEngine.platform]);
    });

    test('platform is always present, even preferred', () {
      expect(
        resolveTtsEngines(
          isWeb: false,
          available: {},
          preferred: TtsEngine.platform,
        ),
        [TtsEngine.platform],
      );
    });
  });
}
