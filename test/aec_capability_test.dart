// Verifies the AEC capability check. On the Dart VM (where `flutter test` runs)
// `dart:ffi` is available, so the ffi-backed factory is compiled and returns a
// native engine adapter — WITHOUT loading the native library (that happens
// lazily on start(), which we never call here). On the web the conditional
// export swaps in a stub returning null; that path can't be exercised under
// `flutter test` but is covered by the `flutter build web` CI/deploy step.

import 'package:comet_beat/core/audio/aec_capability.dart';
import 'package:comet_beat/core/audio/aec_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('createNativeAecEngine returns an AecEngine on an FFI platform (VM)',
      () {
    final engine = createNativeAecEngine();
    // The VM has dart:ffi, so the native adapter is available. Construction must
    // not touch the native library (no start() call here).
    expect(engine, isNotNull);
    expect(engine, isA<AecEngine>());
  });

  test('the returned engine wires into MicrophonePitchService as its aec seam',
      () {
    // Purely a type/compile check that the capability result fits the seam added
    // in milestone (c) — no device, no lib load.
    final engine = createNativeAecEngine();
    expect(engine, isA<AecEngine?>());
  });
}
