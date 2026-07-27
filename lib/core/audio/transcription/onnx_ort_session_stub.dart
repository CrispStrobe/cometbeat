// Web / no-dart:io fallback: no native ONNX Runtime. `fromBytes` returns null,
// so every onnx_ffi_* provider is absent and the resolver falls back to the
// pure-Dart onnx_runtime_dart path. Signatures mirror the IO impl.

import 'dart:typed_data';

class OrtFfiSession {
  /// No native ORT on web / no-dart:io.
  static bool available() => false;

  static OrtFfiSession? fromBytes(Uint8List bytes) => null;

  Map<String, Float32List> run(
    String inputName,
    Float32List data,
    List<int> shape,
    List<String> outputNames,
  ) =>
      const {};

  /// Native-only: no ORT here, so multi-input inference yields nothing.
  Map<String, Float32List> runMulti(
    Map<String, ({List<num> data, List<int> shape, bool int64})> inputs,
    List<String> outputNames,
  ) =>
      const {};

  void dispose() {}
}
