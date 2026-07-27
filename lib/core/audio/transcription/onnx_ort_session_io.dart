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
  static bool? _available;

  /// Whether the native ONNX Runtime is loadable here — cached after the first
  /// probe. False under `flutter test` / `dart run` / web-via-io (no dylib), so
  /// callers can bail BEFORE reading a (possibly huge) model file they couldn't
  /// use anyway. Never throws.
  static bool available() {
    if (_available != null) return _available!;
    try {
      OrtEnv.instance.init(); // lazily opens libonnxruntime — throws if absent
      _envReady = true;
      return _available = true;
    } catch (_) {
      return _available = false;
    }
  }

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

  /// Run MULTIPLE inputs of MIXED type (int64 or float32) in one pass and return
  /// each requested output flattened to a row-major [Float32List].
  ///
  /// Each input carries its flat row-major [data] (as `List<num>`), its [shape],
  /// and an [int64] flag selecting the tensor's element type: `true` builds an
  /// `Int64List` (e.g. token/id + length inputs), `false` a `Float32List` (e.g.
  /// scales). This is what a TTS graph like Piper VITS needs (`input`+
  /// `input_lengths` int64, `scales` float32) — the single-input [run] above
  /// stays untouched for the transcription callers. Frees every native tensor it
  /// allocates in a `finally`.
  Map<String, Float32List> runMulti(
    Map<String, ({List<num> data, List<int> shape, bool int64})> inputs,
    List<String> outputNames,
  ) {
    final tensors = <String, OrtValue>{};
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outs;
    try {
      inputs.forEach((name, spec) {
        // Int64List / Float32List share only `TypedData`, so keep the branches
        // separate — each passes a concrete List to createTensorWithDataList.
        final tensor = spec.int64
            ? OrtValueTensor.createTensorWithDataList(
                Int64List.fromList([for (final v in spec.data) v.toInt()]),
                spec.shape,
              )
            : OrtValueTensor.createTensorWithDataList(
                Float32List.fromList([for (final v in spec.data) v.toDouble()]),
                spec.shape,
              );
        tensors[name] = tensor;
      });
      outs = _session.run(runOptions, tensors, outputNames);
      final result = <String, Float32List>{};
      for (var i = 0; i < outputNames.length; i++) {
        result[outputNames[i]] = _flatFloat(outs[i]?.value);
      }
      return result;
    } finally {
      for (final t in tensors.values) {
        t.release();
      }
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
