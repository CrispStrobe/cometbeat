// Facade for a minimal native-ONNX-Runtime session, behind a conditional import
// so web/`dart run` still compile (they get the null stub). The IO impl wraps
// the `onnxruntime` Flutter plugin (native ORT via FFI); the stub has no ORT.
// This is the ONE place that touches `package:onnxruntime`, so the rest of the
// transcription code stays runtime-agnostic (it speaks Float32List in/out).

export 'onnx_ort_session_stub.dart'
    if (dart.library.io) 'onnx_ort_session_io.dart';
