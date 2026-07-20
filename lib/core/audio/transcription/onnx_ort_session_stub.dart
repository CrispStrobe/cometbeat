// Web / no-dart:io fallback: no native ONNX Runtime. `fromBytes` returns null,
// so every onnx_ffi_* provider is absent and the resolver falls back to the
// pure-Dart onnx_runtime_dart path. Signatures mirror the IO impl.

import 'dart:typed_data';

class OrtFfiSession {
  static OrtFfiSession? fromBytes(Uint8List bytes) => null;

  Map<String, Float32List> run(
    String inputName,
    Float32List data,
    List<int> shape,
    List<String> outputNames,
  ) =>
      const {};

  void dispose() {}
}
