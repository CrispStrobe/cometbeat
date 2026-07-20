// Facade for the native-ONNX-Runtime ("onnxFfi") transcription providers. The
// SAME .onnx models the pure-Dart onnx_runtime_dart path uses (CREPE for F0
// today), run on native ORT via FFI for a GPU-accelerated in-app path. Behind a
// conditional import: web / `dart run` get the null stubs, so the resolver
// falls back to the pure-Dart onnx path. NOT usable from the CLI (the plugin
// needs a Flutter app build) — that's what the pure-Dart onnx + CrispASR-CLI
// paths are for.

export 'onnx_ffi_provider_stub.dart'
    if (dart.library.io) 'onnx_ffi_provider_io.dart';
