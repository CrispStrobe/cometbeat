// A thin wrapper over the `onnxruntime` Flutter plugin (native ORT via FFI):
// load a model from bytes, run one float input → named float outputs (flat,
// row-major). dart:io only — reached solely via onnx_ort_session.dart's
// conditional import.
//
// Everything is defensive: constructing the session lazily opens the native
// `libonnxruntime` dylib (via OrtEnv), which is ONLY present in an actual app
// build (macOS/Win/Linux/Android/iOS) — under `flutter test` / `dart run` it
// throws, so [fromBytes] returns null and the caller falls back. So this never
// crashes a headless run; it just yields "no native ORT here".

import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

class OrtFfiSession {
  OrtFfiSession._(this._session);

  final OrtSession _session;
  static bool _envReady = false;

  /// Build a session from raw `.onnx` bytes, or null if the native ORT runtime
  /// isn't loadable here (headless test, web-via-io, missing dylib) or the
  /// model is malformed. Never throws.
  static OrtFfiSession? fromBytes(Uint8List bytes) {
    try {
      if (!_envReady) {
        // First access lazily opens libonnxruntime — throws when absent.
        OrtEnv.instance.init();
        _envReady = true;
      }
      final session = OrtSession.fromBuffer(bytes, OrtSessionOptions());
      return OrtFfiSession._(session);
    } catch (_) {
      return null;
    }
  }

  /// Run [data] (a flat, row-major tensor of [shape]) as the single input
  /// [inputName]; return each requested [outputNames] as a flat, row-major
  /// Float32List. Frees the native tensors it allocates.
  Map<String, Float32List> run(
    String inputName,
    Float32List data,
    List<int> shape,
    List<String> outputNames,
  ) {
    final input = OrtValueTensor.createTensorWithDataList(data, shape);
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outs;
    try {
      outs = _session.run(runOptions, {inputName: input}, outputNames);
      final result = <String, Float32List>{};
      for (var i = 0; i < outputNames.length; i++) {
        result[outputNames[i]] = _flatFloat(outs[i]?.value);
      }
      return result;
    } finally {
      input.release();
      runOptions.release();
      outs?.forEach((o) => o?.release());
    }
  }

  void dispose() => _session.release();
}

/// Flatten ORT's nested `List<List<...>>` float output back to a flat,
/// row-major Float32List (the shape the decoders expect).
Float32List _flatFloat(Object? value) {
  final out = <double>[];
  void rec(Object? x) {
    if (x is List) {
      for (final e in x) {
        rec(e);
      }
    } else if (x is num) {
      out.add(x.toDouble());
    }
  }

  rec(value);
  return Float32List.fromList(out);
}
