// Facade for the CrispASR-CLI CREPE F0 estimator (native only, behind a
// conditional import so a web build still compiles). The IO impl shells out to
// `crispasr --pitch` (ggml CREPE, MIT — §"crepe" branch: cos=1.0 vs torchcrepe);
// the stub returns null (web / no binary), so the router falls back to the
// pure-Dart / onnx_runtime_dart F0 path.

export 'crispasr_pitch_stub.dart' if (dart.library.io) 'crispasr_pitch_io.dart';
